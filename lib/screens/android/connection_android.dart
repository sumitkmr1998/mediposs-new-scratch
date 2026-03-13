import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../shared/services/discovery_service.dart';

class ConnectionAndroid extends StatefulWidget {
  const ConnectionAndroid({super.key});

  @override
  State<ConnectionAndroid> createState() => _ConnectionAndroidState();
}

class _ConnectionAndroidState extends State<ConnectionAndroid> {
  final _ipCtrl = TextEditingController();
  bool _testing = false;
  bool? _reachable;
  String? _errorMsg;

  Future<void> _autoDetect() async {
    setState(() {
      _testing = true;
      _errorMsg = null;
      _reachable = null;
    });
    final ip = await DiscoveryService.discoverHub();
    if (!mounted) return;

    if (ip != null) {
      _ipCtrl.text = ip;
      // Flawless experience: automatically test and connect if found
      final sync = context.read<SyncService>();
      final ok = await sync.testConnection(ip);
      if (mounted) {
        setState(() {
          _testing = false;
          _reachable = ok;
        });
        if (ok) {
          _connect(); // Auto-connect if health check passes
        }
      }
    } else {
      setState(() => _testing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not find Hub automatically. Please check if Hub is running on the same Wi-Fi.'),
          backgroundColor: AppTheme.warning,
        ));
      }
    }
  }

  Future<void> _test() async {
    if (_ipCtrl.text.isEmpty) return;
    setState(() {
      _testing = true;
      _reachable = null;
      _errorMsg = null;
    });
    final sync = context.read<SyncService>();
    final ok = await sync.testConnection(_ipCtrl.text.trim());
    if (mounted) {
      setState(() {
        _testing = false;
        _reachable = ok;
      });
    }
  }

  Future<void> _connect() async {
    if (_testing) return;
    final sync = context.read<SyncService>();
    setState(() {
      _isConnecting = true;
      _errorMsg = null;
    });

    final error = await sync.connect(_ipCtrl.text.trim());

    if (mounted) {
      if (error != null) {
        setState(() {
          _errorMsg = error;
          _isConnecting = false;
        });
      } else {
        // Just pull users for the Login Screen
        await sync.pullUsers();
        if (mounted) {
          setState(() => _isConnecting = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Hub Paired Successfully!'),
            backgroundColor: AppTheme.success,
          ));
          // Provide subtle haptic/visual cue of success if needed
        }
      }
    }
  }

  bool _isConnecting = false;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Hub')),
      body: Center(
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
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ipCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Hub IP Address (e.g. 192.168.1.5)',
                    prefixIcon: const Icon(Icons.computer),
                    suffixIcon: _testing
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : _reachable == null
                            ? null
                            : Icon(
                                _reachable! ? Icons.check_circle : Icons.cancel,
                                color: _reachable!
                                    ? AppTheme.success
                                    : AppTheme.danger),
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
                    child: Text(_errorMsg!,
                        style: const TextStyle(color: AppTheme.danger)),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (sync.isSyncing || _isConnecting) ? null : _connect,
                    icon: (sync.isSyncing || _isConnecting)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.link),
                    label: Text((sync.isSyncing || _isConnecting)
                        ? 'Pairing...'
                        : 'Pair with Hub'),
                  ),
                ),
                if (sync.isConnected || _reachable == true) ...[
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
                              style: const TextStyle(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
