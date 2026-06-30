import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/services/sync_service.dart';
import '../../widgets/shop_selection_dialog.dart';
import '../../shared/services/global_navigation_service.dart';
import '../../theme/app_theme.dart';
import '../../shared/services/discovery_service.dart';
import 'qr_scanner_screen.dart';
import 'opd/remote_camera_screen_android.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../shared/services/firebase_sync_service.dart';
import '../../shared/providers/settings_provider.dart';
import 'package:battery_optimization_helper/battery_optimization_helper.dart';

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
  String _connectionMode = 'auto';
  String _cloudflareUrl = '';
  bool _isFetchingCloudflare = false;
  Timer? _hubCheckTimer;
  bool _isHubBackOnline = false;

  @override
  void dispose() {
    _hubCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>().settings;
    _ipCtrl.text = s.hubIp ?? '';
    _connectionMode = s.connectionMode;
    _cloudflareUrl = s.cloudflareUrl;
    _fetchCloudflareUrl();
    _checkBatteryOptimization();

    // Start periodic Hub availability check for Cloud Mode
    _hubCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      final sync = context.read<SyncService>();
      if (sync.isCloudMode && sync.hubIp != null) {
        final reachable = await sync.testConnection(sync.hubIp!);
        if (reachable != _isHubBackOnline) {
          setState(() => _isHubBackOnline = reachable);
        }
      }
    });
  }

  Future<void> _checkBatteryOptimization() async {
    final isOptimized = await BatteryOptimizationHelper.isBatteryOptimizationEnabled();
    if (isOptimized && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Background Sync Optimization'),
          content: const Text(
              'For real-time background syncing to work reliably, please disable battery optimization for MediPoss.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                BatteryOptimizationHelper.openBatteryOptimizationSettings();
                Navigator.pop(ctx);
              },
              child: const Text('Disable Now'),
            ),
          ],
        ),
      );
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

  Future<void> _selectShopPartition() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Fetching available shops...'),
          ],
        ),
      ),
    );

    final List<String> shopIds = await FirebaseSyncService.instance.fetchShopIds();

    if (!mounted) return;
    Navigator.pop(context); // Dismiss loading

    String? selectedShop;
    final writeInController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.store, color: AppTheme.primary),
                SizedBox(width: 8),
                Text('Select Shop Partition'),
              ],
            ),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose the partition for your Windows Hub:',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (shopIds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No active shops detected in Firebase.',
                          style: TextStyle(fontSize: 12, color: AppTheme.danger)),
                    )
                  else
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: shopIds.length,
                          itemBuilder: (_, i) {
                            final id = shopIds[i];
                            final isSelected = selectedShop == id;
                            return ListTile(
                              title: Text(id, style: const TextStyle(fontSize: 14)),
                              selected: isSelected,
                              trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primary) : null,
                              dense: true,
                              onTap: () {
                                setDialogState(() {
                                  selectedShop = id;
                                  writeInController.text = id;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: writeInController,
                    decoration: const InputDecoration(
                      labelText: 'Shop ID / Partition Name',
                      hintText: 'e.g. clinic_central',
                      isDense: true,
                    ),
                    onChanged: (val) {
                      if (selectedShop != val) {
                        setDialogState(() {
                          selectedShop = null;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final finalId = writeInController.text.trim();
                  if (finalId.isEmpty) return;
                  Navigator.pop(ctx);
                  
                  final settingsProv = context.read<SettingsProvider>();
                  final s = settingsProv.settings;
                  s.shopId = finalId;
                  settingsProv.save(s);
                  
                  _fetchCloudflareUrl();
                },
                child: const Text('Select'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (result != null && mounted) {
      try {
        final data = jsonDecode(result) as Map<String, dynamic>;
        if (data['type'] == 'remote_camera') {
          final hubIp = data['hubIp'];
          final patientUhid = data['patientUhid'];
          final patientName = data['patientName'];

          if (hubIp != null) {
            _ipCtrl.text = hubIp;
            await _connect();
            
            if (mounted && context.read<SyncService>().isConnected) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RemoteCameraScreenAndroid(
                    patientUhid: patientUhid,
                    patientName: patientName,
                    hubIp: hubIp,
                  ),
                ),
              );
            }
          }
        } else {
          // Maybe it's just the IP?
          _ipCtrl.text = result;
        }
      } catch (e) {
        // Fallback: treat raw string as IP
        _ipCtrl.text = result;
      }
    }
  }

  Future<void> _autoDetect() async {
    setState(() {
      _testing = true;
      _errorMsg = null;
      _reachable = null;
    });

    // Fetch the latest cloudflare tunnel URL first so the UI and fallback are always up-to-date
    await _fetchCloudflareUrl();

    final settings = context.read<SettingsProvider>().settings;
    // 1. Try Local Network Discovery (UDP)
    String? ip = await DiscoveryService.discoverHub(targetShopId: settings.shopId);

    // 2. If local fails, try Cloud Discovery (Firebase)
    if (ip == null && _cloudflareUrl.isNotEmpty) {
      ip = _cloudflareUrl;
      debugPrint('Auto-detected Hub via Cloudflare: $ip');
    }

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
      setState(() {
        _testing = false;
        _reachable = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not find Hub. Please check if Hub is running or use Cloud Mode.'),
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
        // Start WebSocket for real-time triggers/sync
        final wsService = context.read<WebSocketService>();
        wsService.connect(sync.hubIp!, sync.secret);

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
                ElevatedButton.icon(
                  onPressed: _testing ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Hub QR'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
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
                // --- Shop Partition Selector ---
                Row(
                  children: [
                    Text('Shop Partition:',
                        style: TextStyle(
                            color: context.textMutedColor,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _selectShopPartition,
                      icon: const Icon(Icons.store, size: 14),
                      label: Text(
                        context.watch<SettingsProvider>().settings.shopId.isEmpty
                            ? 'default_shop'
                            : context.watch<SettingsProvider>().settings.shopId,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
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
                if (_errorMsg != null || _reachable == false) ...[
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
                        const Expanded(
                          child: Text(
                            'Active in Cloud Mode (Firebase)',
                            style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
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
                              style: const TextStyle(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.bold)),
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Full Sync Complete'), backgroundColor: AppTheme.success));
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
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
