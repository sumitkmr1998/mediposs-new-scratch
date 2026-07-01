import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/services/objectbox_service.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _showAdvanced = false;
  bool _autoConnectToPrevious = true;
  bool _isScanning = false;

  Future<List<String>> _getRecentShopIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('recentShopIds') ?? [];
  }

  Future<void> _addRecentShopId(String shopId) async {
    if (shopId.isEmpty || shopId == 'default_shop') return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('recentShopIds') ?? [];
    list.remove(shopId);
    list.insert(0, shopId);
    if (list.length > 5) {
      list.removeLast();
    }
    await prefs.setStringList('recentShopIds', list);
  }

  Future<void> _loadAutoConnectPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoConnectToPrevious = prefs.getBool('autoConnectToPreviousHub') ?? true;
      });
    }
  }

  Future<void> _saveAutoConnectPref(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoConnectToPreviousHub', value);
    if (mounted) {
      setState(() {
        _autoConnectToPrevious = value;
      });
    }
  }

  @override
  void dispose() {
    _hubCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAutoConnectPref();
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

    // Auto-detect Hub on first launch if no Hub Address is configured
    if (s.hubIp == null || s.hubIp!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoDetect();
      });
    }
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
    final List<String> recentShops = await _getRecentShopIds();

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
                  
                  // Recently used chips list
                  if (recentShops.isNotEmpty) ...[
                    const Text(
                      'Recently Used:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: recentShops.map((id) {
                        return ActionChip(
                          avatar: const Icon(Icons.history, size: 14, color: AppTheme.primary),
                          label: Text(id, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            setDialogState(() {
                              selectedShop = id;
                              writeInController.text = id;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (shopIds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No active shops detected in Firebase.',
                          style: TextStyle(fontSize: 12, color: AppTheme.danger)),
                    )
                  else ...[
                    const Text(
                      'Available in Cloud:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 150),
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
                  ],
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
                onPressed: () async {
                  final finalId = writeInController.text.trim();
                  if (finalId.isEmpty) return;
                  Navigator.pop(ctx);
                  
                  await _addRecentShopId(finalId);
                  
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

  void _showNetworkSelectionDialog(List<Map<String, dynamic>> hubs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.network_wifi, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Select Active Hub'),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Multiple active hubs or tunnels were detected. Choose which one to connect to:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: hubs.length,
                  itemBuilder: (_, i) {
                    final hub = hubs[i];
                    final ip = hub['ip'] as String;
                    final shopId = hub['shopId'] as String;
                    final isLocal = hub['isLocal'] as bool;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          isLocal ? Icons.router : Icons.cloud,
                          color: isLocal ? Colors.green : Colors.blue,
                        ),
                        title: Text(
                          shopId,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          ip,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLocal ? Colors.green.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isLocal ? 'Local' : 'Cloud',
                            style: TextStyle(
                              color: isLocal ? Colors.green : Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          _ipCtrl.text = ip;
                          
                          // Save to Shop ID history
                          await _addRecentShopId(shopId);
                          
                          final settingsProv = context.read<SettingsProvider>();
                          final s = settingsProv.settings;
                          s.shopId = shopId;
                          s.hubIp = ip;
                          settingsProv.save(s);
                          
                          _connect();
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _autoDetect() async {
    setState(() {
      _isScanning = true;
      _testing = true;
      _errorMsg = null;
      _reachable = null;
    });

    final List<Map<String, dynamic>> results = [];
    try {
      final scans = await Future.wait([
        DiscoveryService.discoverHubs(),
        FirebaseSyncService.instance.getAllActiveCloudTunnels(),
      ]).timeout(const Duration(seconds: 4));
      
      results.addAll(scans[0]);
      results.addAll(scans[1]);
    } catch (_) {}

    // Save all scanned shop IDs to history automatically
    for (final hub in results) {
      final shopId = hub['shopId'] as String? ?? '';
      if (shopId.isNotEmpty && shopId != 'Unknown') {
        await _addRecentShopId(shopId);
      }
    }

    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _testing = false;
    });

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No active hubs detected. Try scanning the QR Code or manual entry.'),
        backgroundColor: AppTheme.warning,
      ));
    } else if (results.length == 1) {
      final hub = results.first;
      _ipCtrl.text = hub['ip'];
      final shopId = hub['shopId'];
      await _addRecentShopId(shopId);
      
      final settingsProv = context.read<SettingsProvider>();
      final s = settingsProv.settings;
      s.shopId = shopId;
      s.hubIp = hub['ip'];
      settingsProv.save(s);

      final sync = context.read<SyncService>();
      final ok = await sync.testConnection(hub['ip']);
      if (mounted) {
        setState(() {
          _reachable = ok;
        });
        if (ok) {
          _connect();
        }
      }
    } else {
      _showNetworkSelectionDialog(results);
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
    final settingsProvider = context.watch<SettingsProvider>();
    final currentShopId = settingsProvider.settings.shopId.isEmpty ? 'default_shop' : settingsProvider.settings.shopId;

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
                  // --- Clean & Visual Header ---
                  const Icon(
                    Icons.sync,
                    size: 64,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'MediPoss Hub Connection',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect this Android terminal with the MediPoss Hub desktop application to sync users, inventory, and sales.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.textMutedColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // --- Active Shop ID Badge ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.store, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Shop ID: $currentShopId',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // --- First-Class Pairing Actions ---
                  ElevatedButton.icon(
                    onPressed: _testing ? null : _scanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Hub QR Code'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54),
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _autoDetect,
                    icon: const Icon(Icons.search),
                    label: const Text('Auto-Detect Hub'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Collapsible Manual/Advanced Configuration ---
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: context.borderColor.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.tune, size: 20),
                          title: const Text(
                            'Configure Manually',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          trailing: Icon(
                            _showAdvanced ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 20,
                          ),
                          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                        ),
                        if (_showAdvanced) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text(
                                      'Shop Partition:',
                                      style: TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: _selectShopPartition,
                                      icon: const Icon(Icons.store, size: 14),
                                      label: Text(
                                        currentShopId,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _ipCtrl,
                                  keyboardType: TextInputType.text,
                                  decoration: InputDecoration(
                                    labelText: 'Hub Address',
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
                                                color: _reachable! ? AppTheme.success : AppTheme.danger,
                                              ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _testing ? null : _test,
                                    child: const Text('Test Connection'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: Checkbox(
                                        value: _autoConnectToPrevious,
                                        onChanged: (val) {
                                          if (val != null) {
                                            _saveAutoConnectPref(val);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Auto-connect on restart',
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: (sync.isSyncing || _isConnecting) ? null : _connect,
                                    icon: (sync.isSyncing || _isConnecting)
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.link),
                                    label: Text((sync.isSyncing || _isConnecting) ? 'Pairing...' : 'Pair with Hub'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // --- Connection Status Display ---
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                      ),
                    ),
                  ],

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
                                  'Hub is Offline.',
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
                            onPressed: () {
                              final savedId = ObjectBoxService.instance.settings.shopId;
                              if (savedId.isNotEmpty) {
                                sync.enterCloudMode(savedId);
                              } else {
                                showShopSelectionDialog(context);
                              }
                            },
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
