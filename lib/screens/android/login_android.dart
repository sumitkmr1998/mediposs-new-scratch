import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../theme/app_theme.dart';

import '../../shared/models/app_user.dart';

class LoginAndroid extends StatefulWidget {
  const LoginAndroid({super.key});

  @override
  State<LoginAndroid> createState() => _LoginAndroidState();
}

class _LoginAndroidState extends State<LoginAndroid> {
  AppUser? _selectedUser;
  String _pin = '';
  bool _error = false;
  bool _isLoading = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() {
          _version = info.version;
        });
      }
    });
  }

  void _tap(String digit) {
    if (_pin.length < 6) {
      setState(() {
        _pin += digit;
        _error = false;
      });
    }
    if (_pin.length == 4 || _pin.length == 6) {
      if (!_isLoading) _tryLogin();
    }
  }

  void _backspace() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _tryLogin() async {
    if (_selectedUser == null || _isLoading) return;
    final auth = context.read<AuthProvider>();

    setState(() {
      _isLoading = true;
      _error = false;
    });

    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      // Local Auth (Windows/Web Hub)
      if (auth.loginWithUser(_selectedUser!, _pin)) {
        // Success
      } else {
        setState(() {
          _error = true;
          _pin = '';
        });
      }
      setState(() => _isLoading = false);
    } else {
      // Companion App Auth (Android)
      try {
        final sync = context.read<SyncService>();
        final errorMsg = await sync.login(_selectedUser!.name, _pin);

        if (errorMsg == null && mounted) {
          // Auth passed on Hub, trigger incremental sync
          await sync.syncAll(isFullSync: false);

          if (!mounted) return;

          // Reload providers with the new Hub data
          context.read<InventoryProvider>().load();
          context.read<PatientProvider>().load();
          context.read<OpdProvider>().loadAll();
          context.read<SalesProvider>().load();

          // Connect WS only if Hub is available
          if (sync.hubIp != null && !sync.isCloudMode) {
            context.read<WebSocketService>().connect(sync.hubIp!, sync.secret);
          }

          // Finally, tell AuthProvider we are logged in so `main.dart` navigates
          // We use forceLogin because Hub already approved the PIN.
          // CRITICAL: Update the user object with the permissions returned by the Hub
          if (sync.lastUserMap != null) {
            final updatedUser = AppUser.fromJson(sync.lastUserMap!);
            // Ensure local ID is preserved if possible, but forceLogin will use this object anyway
            auth.forceLogin(updatedUser);
          } else {
            auth.forceLogin(_selectedUser!);
          }
        } else {
          if (mounted) {
            setState(() {
              _error = true;
              _pin = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(errorMsg ?? 'Authentication Failed'),
              backgroundColor: AppTheme.danger,
            ));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Login error: $e'),
            backgroundColor: AppTheme.danger,
          ));
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final users = auth.getAllUsers().where((u) => u.isActive).toList();

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.backspace) {
              _backspace();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              _tryLogin();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() {
                _selectedUser = null;
                _pin = '';
                _error = false;
              });
              return KeyEventResult.handled;
            }
            final char = event.character;
            if (char != null && int.tryParse(char) != null) {
              _tap(char);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_pharmacy,
                        size: 48, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('MediPoss',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900, color: AppTheme.primary)),
                      if (_version.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('v$_version',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.textMutedColor)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Medical Store Management',
                      style: TextStyle(color: context.textMutedColor)),
                  const SizedBox(height: 12),
                  if (context.watch<SyncService>().isCloudMode)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.warning.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, size: 14, color: AppTheme.warning),
                          SizedBox(width: 6),
                          Text('Cloud Mode (Hub Offline)',
                              style: TextStyle(
                                  color: AppTheme.warning,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 28),

                  if (_selectedUser == null) ...[
                    Text('Select User',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: users.map((u) {
                        return InkWell(
                          onTap: () => setState(() => _selectedUser = u),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 100,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor:
                                      AppTheme.primary.withValues(alpha: 0.1),
                                  child: Text(u.name[0].toUpperCase(),
                                      style: const TextStyle(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 8),
                                Text(u.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                                Text(u.role,
                                    style: TextStyle(
                                        color: context.textMutedColor,
                                        fontSize: 10)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    // Change Hub Button for Mobile
                    if (!kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS))
                      TextButton.icon(
                        onPressed: () {
                          context.read<SyncService>().disconnect();
                          // SyncService notifies listeners and main.dart will push ConnectionScreen
                        },
                        icon: const Icon(Icons.hub),
                        label: const Text('Change Hub'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                        ),
                      ),
                  ] else ...[
                    // PIN Phase
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => setState(() => _selectedUser = null),
                          tooltip: 'Back to User Selection (Esc)',
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedUser!.name,
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold)),
                            Text(_selectedUser!.role,
                                style: TextStyle(
                                    color: context.textMutedColor, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // PIN Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final filled = i < _pin.length;
                        return Container(
                          margin: const EdgeInsets.all(8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _error
                                ? AppTheme.danger
                                : filled
                                    ? AppTheme.primary
                                    : context.borderColor,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : _error
                              ? const Text('Incorrect PIN',
                                  key: ValueKey('err'),
                                  style: TextStyle(color: AppTheme.danger))
                              : Text('Enter PIN for ${_selectedUser!.name}',
                                  key: const ValueKey('prompt'),
                                  style:
                                      TextStyle(color: context.textMutedColor)),
                    ),
                    const SizedBox(height: 32),

                    // Number Pad
                    SizedBox(
                      width: 320,
                      child: GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.4,
                        children: [
                          ...[
                            '1',
                            '2',
                            '3',
                            '4',
                            '5',
                            '6',
                            '7',
                            '8',
                            '9'
                          ].map((d) => _PinBtn(label: d, onTap: () => _tap(d))),
                          _PinBtn(
                              label: '⌫',
                              onTap: _backspace,
                              color: context.textMutedColor),
                          _PinBtn(label: '0', onTap: () => _tap('0')),
                          _PinBtn(
                              label: '✓',
                              onTap: _isLoading ? () {} : _tryLogin,
                              color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  Text('Default PIN: 1234',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.textMutedColor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _PinBtn({required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: (color ?? context.cardColor).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (color ?? context.borderColor)),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color ?? context.textColor,
            )),
      ),
    );
  }
}
