import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../shared/services/discovery_service.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../shared/services/firebase_sync_service.dart';
import '../../shared/providers/settings_provider.dart';

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

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>().settings;
    _ipCtrl.text = s.hubIp ?? '';
    _connectionMode = s.connectionMode;
    _cloudflareUrl = s.cloudflareUrl;
    _fetchCloudflareUrl();
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
    
    // 1. Try Local Network Discovery (UDP)
    String? ip = await DiscoveryService.discoverHub();
    
    // 2. If local fails, try Cloud Discovery (Firebase)
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

  Future<void> _connect() async {
    final sync = context.read<SyncService>();
    setState(() => _errorMsg = null);

    final error = await sync.connect(_ipCtrl.text.trim());

    if (error != null) {
      setState(() => _errorMsg = error);
    } else {
      // Just pull users for the Login Screen; real data sync happens after login
      await sync.pullUsers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Hub Paired!'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

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
                const SizedBox(height: 24),
                // --- Hybrid Mode Selector ---
                Row(
                  children: [
                    Text('Sync Mode:',
                        style: TextStyle(
                            color: context.textMutedColor,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _connectionMode,
                      dropdownColor: context.surfaceColor,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                            value: 'auto', child: Text('Auto (Hybrid)')),
                        DropdownMenuItem(
                            value: 'local', child: Text('Local Only')),
                        DropdownMenuItem(
                            value: 'cloudflare', child: Text('Tunnel Only')),
                        DropdownMenuItem(
                            value: 'firebase', child: Text('Cloud Only')),
                      ],
                      onChanged: (val) {
                        if (val != null) _saveMode(val);
                      },
                    ),
                  ],
                ),
                if (_connectionMode == 'cloudflare' ||
                    _connectionMode == 'auto') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.textMutedColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: context.borderColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_done,
                            size: 16, color: AppTheme.primaryLight),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _cloudflareUrl.isEmpty
                                ? 'Fetching Tunnel...'
                                : _cloudflareUrl,
                            style: const TextStyle(
                                fontSize: 12, overflow: TextOverflow.ellipsis),
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
                                Clipboard.setData(
                                    ClipboardData(text: _cloudflareUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Tunnel URL copied!')));
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
                    onPressed: sync.isSyncing ? null : _connect,
                    icon: sync.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.link),
                    label:
                        Text(sync.isSyncing ? 'Pairing...' : 'Pair with Hub'),
                  ),
                ),
                if (sync.isConnected) ...[
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
                        Text('Connected to ${sync.hubIp}',
                            style: const TextStyle(color: AppTheme.success)),
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
