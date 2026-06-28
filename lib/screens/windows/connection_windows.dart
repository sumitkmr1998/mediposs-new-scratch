import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../shared/services/discovery_service.dart';
import '../../widgets/shop_selection_dialog.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/services/firebase_sync_service.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/models/shop_profile.dart';
import '../../shared/services/objectbox_service.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/providers/prescription_provider.dart';
import '../../shared/providers/template_provider.dart';

class ConnectionWindows extends StatefulWidget {
  const ConnectionWindows({super.key});

  @override
  State<ConnectionWindows> createState() => _ConnectionWindowsState();
}

class _ConnectionWindowsState extends State<ConnectionWindows> {
  final _ipCtrl = TextEditingController();
  bool _testing = false;
  bool? _reachable;
  String? _errorMsg;
  String _connectionMode = 'auto';
  String _cloudflareUrl = '';
  bool _isFetchingCloudflare = false;

  List<ShopProfile> _savedShops = [];
  bool _showManualSetup = false;
  bool _isLoadingShops = true;
  String _isConnectingProfileId = '';
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedShops();
    final s = context.read<SettingsProvider>().settings;
    _ipCtrl.text = s.hubIp ?? '';
    _connectionMode = s.connectionMode;
    _cloudflareUrl = s.cloudflareUrl;
    _fetchCloudflareUrl();
  }

  Future<void> _loadSavedShops() async {
    setState(() => _isLoadingShops = true);
    final shops = await ShopProfileManager.getSavedShops();
    if (mounted) {
      setState(() {
        _savedShops = shops;
        _isLoadingShops = false;
        if (shops.isEmpty) {
          _showManualSetup = true;
        }
      });
    }
  }

  Future<void> _fetchCloudflareUrl() async {
    setState(() => _isFetchingCloudflare = true);
    try {
      final status = await FirebaseSyncService.instance.getHubStatus();
      if (status != null && mounted) {
        setState(() {
          _cloudflareUrl = status['cloudflareUrl'] ?? _cloudflareUrl;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isFetchingCloudflare = false);
    }
  }

  void _saveMode(String mode) {
    final settingsProv = context.read<SettingsProvider>();
    final s = settingsProv.settings;
    s.connectionMode = mode;
    settingsProv.save(s);
    setState(() => _connectionMode = mode);
  }

  Future<void> _autoDetect() async {
    setState(() => _testing = true);
    String? ip = await DiscoveryService.discoverHub();
    if (ip == null) {
      final status = await FirebaseSyncService.instance.getHubStatus();
      if (status != null && status['cloudflareUrl'] != null) {
        ip = status['cloudflareUrl'];
      }
    }
    setState(() => _testing = false);
    if (ip != null) {
      _ipCtrl.text = ip;
      _test();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not find Hub. Please check if Hub is running.'),
        ));
      }
    }
  }

  Future<void> _test() async {
    if (_ipCtrl.text.isEmpty) return;
    setState(() {
      _testing = true;
      _reachable = null;
    });
    final sync = context.read<SyncService>();
    final ok = await sync.testConnection(_ipCtrl.text.trim());
    setState(() {
      _testing = false;
      _reachable = ok;
    });
  }

  Future<void> _connectShopProfile(ShopProfile profile) async {
    setState(() {
      _isConnecting = true;
      _errorMsg = null;
      _isConnectingProfileId = profile.shopId;
    });

    final sync = context.read<SyncService>();
    bool success = false;

    if (profile.localIp.isNotEmpty) {
      final err = await sync.connect(profile.localIp);
      if (err == null) success = true;
    }

    if (!success && profile.cloudflareUrl.isNotEmpty) {
      final err = await sync.connect(profile.cloudflareUrl);
      if (err == null) success = true;
    }

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _isConnectingProfileId = '';
      });
      if (success) {
        final wsService = context.read<WebSocketService>();
        wsService.connect(sync.hubIp!, sync.secret);
        await sync.pullUsers();
        if (mounted) {
          context.read<SettingsProvider>().load();
          context.read<InventoryProvider>().load();
          context.read<SalesProvider>().load();
          context.read<PatientProvider>().load();
          context.read<OpdProvider>().loadAll();
          context.read<PrescriptionProvider>().load();
          context.read<TemplateProvider>().load();
        }
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Connection Failed'),
            content: Text('Cannot connect to Hub for "${profile.shopName}" (${profile.shopId}) locally or via cloud. Would you like to work offline?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await ObjectBoxService.init(shopId: profile.shopId);
                  await ShopProfileManager.setActiveShopId(profile.shopId);
                  sync.enterCloudMode(profile.shopId);
                  if (mounted) {
                    context.read<SettingsProvider>().load();
                    context.read<InventoryProvider>().load();
                    context.read<SalesProvider>().load();
                    context.read<PatientProvider>().load();
                    context.read<OpdProvider>().loadAll();
                    context.read<PrescriptionProvider>().load();
                    context.read<TemplateProvider>().load();
                  }
                },
                child: const Text('Work Offline (Cloud Mode)'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _connect() async {
    if (_testing || _isConnecting) return;
    final sync = context.read<SyncService>();
    setState(() {
      _isConnecting = true;
      _errorMsg = null;
    });

    final error = await sync.connect(_ipCtrl.text.trim());

    if (error == 'RESTART_REQUIRED') {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restart Required'),
          content: const Text(
              'Switching to Terminal Mode requires a full application restart to load the terminal database and apply network changes.'),
          actions: [
            ElevatedButton(
              onPressed: () async {
                await Future.delayed(const Duration(milliseconds: 1000));
                exit(0);
              },
              child: const Text('Restart Now'),
            ),
          ],
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isConnecting = false;
        if (error != null) {
          _errorMsg = error;
        }
      });
      if (error == null) {
        await sync.pullUsers();
        if (!mounted) return;
        final settingsProv = context.read<SettingsProvider>();
        final s = settingsProv.settings;
        s.isWindowsClient = true;
        s.hubIp = _ipCtrl.text.trim();
        settingsProv.save(s);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Hub Paired!'),
          backgroundColor: AppTheme.success,
        ));
      }
    }
  }

  Future<void> _switchToHubMode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch to Hub Mode?'),
        content: const Text(
          'Are you sure you want to switch this app back to Hub Mode? '
          'This will configure the app to run as the primary database server and requires a restart.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch & Restart'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isTerminalMode', false);

    if (!mounted) return;
    final settingsProv = context.read<SettingsProvider>();
    final s = settingsProv.settings;
    s.isWindowsClient = false;
    settingsProv.save(s);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart Required'),
        content: const Text(
            'The mode has been changed to Hub Mode. A full restart is required to spin up the local server and load the primary database.'),
        actions: [
          ElevatedButton(
            onPressed: () async {
              await Future.delayed(const Duration(milliseconds: 1000));
              exit(0);
            },
            child: const Text('Restart Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();

    if (_isLoadingShops) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_showManualSetup && _savedShops.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Select Clinic / Shop')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose a clinic partition to connect to:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _savedShops.length,
                      itemBuilder: (context, index) {
                        final shop = _savedShops[index];
                        final isConnectingThis = _isConnecting && _isConnectingProfileId == shop.shopId;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: context.borderColor.withValues(alpha: 0.5)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                              child: const Icon(Icons.storefront, color: AppTheme.primary),
                            ),
                            title: Text(
                              shop.shopName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ID: ${shop.shopId}', style: TextStyle(color: context.textMutedColor, fontSize: 12)),
                                if (shop.localIp.isNotEmpty)
                                  Text('IP: ${shop.localIp}', style: TextStyle(color: context.textMutedColor, fontSize: 12)),
                              ],
                            ),
                            trailing: isConnectingThis
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Unpair Clinic'),
                                              content: Text('Are you sure you want to unpair "${shop.shopName}"? This will remove it from this list.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unpair', style: TextStyle(color: AppTheme.danger))),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await ShopProfileManager.removeProfile(shop.shopId);
                                            _loadSavedShops();
                                          }
                                        },
                                      ),
                                      const Icon(Icons.chevron_right, color: Colors.grey),
                                    ],
                                  ),
                            onTap: _isConnecting ? null : () => _connectShopProfile(shop),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _showManualSetup = true),
                    icon: const Icon(Icons.add),
                    label: const Text('Pair with New Clinic'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _switchToHubMode,
                    icon: const Icon(Icons.swap_horizontal_circle, color: AppTheme.danger),
                    label: const Text('Switch to Hub Mode'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Hub'),
        leading: _savedShops.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showManualSetup = false),
              )
            : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.router, color: AppTheme.primaryLight),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Enter the IP address of the Windows PC running MediPoss Hub.',
                            style: TextStyle(color: context.textMutedColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _autoDetect,
                    icon: const Icon(Icons.search),
                    label: const Text('Auto-Detect Hub'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text('Sync Mode:',
                          style: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      DropdownButton<String>(
                        value: _connectionMode,
                        dropdownColor: context.surfaceColor,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'auto', child: Text('Auto (Hybrid)')),
                          DropdownMenuItem(value: 'local', child: Text('Local Only')),
                          DropdownMenuItem(value: 'cloudflare', child: Text('Tunnel Only')),
                          DropdownMenuItem(value: 'firebase', child: Text('Cloud Only')),
                        ],
                        onChanged: (val) {
                          if (val != null) _saveMode(val);
                        },
                      ),
                    ],
                  ),
                  if (_connectionMode == 'cloudflare' || _connectionMode == 'auto') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.textMutedColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.borderColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_done, size: 16, color: AppTheme.primaryLight),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _cloudflareUrl.isEmpty ? 'Fetching Tunnel...' : _cloudflareUrl,
                              style: const TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          if (_isFetchingCloudflare)
                            const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              onPressed: () {
                                if (_cloudflareUrl.isNotEmpty) {
                                  Clipboard.setData(ClipboardData(text: _cloudflareUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Tunnel URL copied!')));
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ipCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Hub IP Address (e.g. 192.168.1.5)',
                      prefixIcon: const Icon(Icons.computer),
                      suffixIcon: _testing
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : _reachable == null
                              ? null
                              : Icon(
                                  _reachable! ? Icons.check_circle : Icons.cancel,
                                  color: _reachable! ? AppTheme.success : AppTheme.danger),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: _testing ? null : _test,
                        child: const Text('Test Connection')),
                  ),
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_errorMsg!, style: const TextStyle(color: AppTheme.danger)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: _connectionMode == 'firebase'
                        ? ElevatedButton.icon(
                            onPressed: () => showShopSelectionDialog(context),
                            icon: const Icon(Icons.cloud_sync),
                            label: const Text('Enter Cloud Mode'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              backgroundColor: AppTheme.warning,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: (sync.isSyncing || _isConnecting) ? null : _connect,
                            icon: (sync.isSyncing || _isConnecting)
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.link),
                            label: Text((sync.isSyncing || _isConnecting) ? 'Pairing...' : 'Pair with Hub'),
                          ),
                  ),
                  if (_connectionMode != 'firebase' && (_errorMsg != null || _reachable == false)) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.cloud_off, color: AppTheme.warning),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Hub is currently Offline.',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.warning),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'You can continue in Cloud Mode to view data and make sales via Firebase.',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => showShopSelectionDialog(context),
                            icon: const Icon(Icons.cloud_sync),
                            label: const Text('Enter Cloud Mode'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.warning,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 40),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (sync.isCloudMode) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_done, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Active in Cloud Mode (Shop: ${context.read<SettingsProvider>().settings.shopId})',
                              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () => sync.exitCloudMode(),
                            child: const Text('Exit'),
                          ),
                        ],
                      ),
                    ),
                  ] else if (sync.isConnected || _reachable == true) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppTheme.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Connected to ${sync.hubIp ?? _ipCtrl.text}',
                              style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (sync.isConnected) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starting full data refresh...')));
                        await sync.forceFullSync();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('✅ Full Sync Complete'), backgroundColor: AppTheme.success));
                        }
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Force Full Sync'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 40),
                        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                      ),
                    ),
                  ],
                  const Divider(height: 32),
                  TextButton.icon(
                    onPressed: _switchToHubMode,
                    icon: const Icon(Icons.swap_horizontal_circle, color: AppTheme.danger),
                    label: const Text('Switch to Hub Mode', style: TextStyle(color: AppTheme.danger)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
