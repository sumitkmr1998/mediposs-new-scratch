import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'shared/services/objectbox_service.dart';
import 'shared/services/sync_service.dart';
import 'shared/providers/auth_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/inventory_provider.dart';
import 'shared/providers/sales_provider.dart';
import 'shared/providers/warehouse_provider.dart';
import 'shared/providers/cart_provider.dart';
import 'shared/providers/patient_provider.dart';
import 'shared/providers/opd_provider.dart';
import 'shared/providers/prescription_provider.dart';
import 'shared/providers/template_provider.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/app_shell.dart';
import 'screens/connection_screen.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'shared/services/local_server_service.dart';
import 'shared/services/discovery_service.dart';
import 'shared/services/global_navigation_service.dart';
import 'shared/services/sync_queue_service.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:firebase_core/firebase_core.dart';
import 'shared/services/firebase_sync_service.dart';
import 'shared/services/cloudflare_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize DB FIRST (so settings are available)
  await ObjectBoxService.init();

  // Initialize Firebase (Mobile Only)
  if (defaultTargetPlatform != TargetPlatform.windows) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseSyncService.init();
    } catch (e) {
      debugPrint('Firebase Initialization Failed: $e');
      await FirebaseSyncService.init();
    }
  } else {
    // On Windows, initialize the service dummy so it doesn't crash on access
    await FirebaseSyncService.init();
  }

  try {
    await CloudflareService.init();
  } catch (e) {
    debugPrint('Cloudflare Initialization Failed: $e');
  }

  // 2. Set high refresh rate for Android
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final preferredRate = ObjectBoxService.instance.settings.preferredRefreshRate;
      if (preferredRate <= 0.0) {
        await FlutterDisplayMode.setHighRefreshRate();
      } else {
        final modes = await FlutterDisplayMode.supported;
        final mode = modes.firstWhere(
          (m) => m.refreshRate.toStringAsFixed(1) == preferredRate.toStringAsFixed(1),
          orElse: () => modes.first,
        );
        await FlutterDisplayMode.setPreferredMode(mode);
      }
    } catch (e) {
      debugPrint('Failed to set refresh rate: $e');
    }
  }

  // 3. Setup Base Providers
  final authProvider = AuthProvider();
  final inventoryProvider = InventoryProvider();
  final salesProvider = SalesProvider();
  final warehouseProvider = WarehouseProvider(inventoryProvider);
  final prescriptionProvider = PrescriptionProvider();

  // 4. OPD Providers
  final patientProvider = PatientProvider();
  final opdProvider = OpdProvider();
  final templateProvider = TemplateProvider();

  // 5. Cart Provider
  final cartProvider = CartProvider(
      inventoryProvider, salesProvider, prescriptionProvider, opdProvider);

  final settingsProvider = SettingsProvider();

  final syncService = SyncService();
  final wsService = WebSocketService();
  SyncQueueService.instance.init();

  // Global listener for real-time data sync
  wsService.eventStream.listen((msg) {
    final event = msg['event'];
    debugPrint('Mobile WebSocket Event: $event');
    if (event == 'remote_camera_trigger') {
      GlobalNavigationService.handleRemoteCameraTrigger(msg);
    } else if (event == 'sync_received' || 
               event == 'medicines_updated' || 
               event == 'sales_updated' ||
               event == 'patients_updated' ||
               event == 'appointments_updated') {
      syncService.syncAll().then((_) {
        inventoryProvider.load();
        salesProvider.load();
        patientProvider.load();
        opdProvider.loadAll();
        prescriptionProvider.load();
        templateProvider.load();
      });
    } else if (event == 'settings_updated') {
      syncService.pullSettings().then((_) => settingsProvider.load());
    } else if (event == 'users_updated') {
      syncService.pullUsers().then((_) => authProvider.notifyListeners());
    }
  });

  // Try to auto-connect to a saved Hub IP so companion app skips connection screen
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (isMobile) {
    final connected = await syncService.tryAutoConnect();
    if (connected && syncService.hubIp != null) {
      wsService.connect(syncService.hubIp!, syncService.secret);
    }
  } else if (Platform.isWindows) {
    // Start Hub server immediately on Windows launch
    await LocalServerService.instance.start();
    await DiscoveryService.startAdvertising(
        ObjectBoxService.instance.settings.serverPort);
    
    // Start Cloudflare Tunnel if enabled or always for remote discovery
    await CloudflareService.instance.start();

    // Start Firebase Sync Listener (Tier 3 fallback)
    FirebaseSyncService.instance.startQueueListener((delta) {
      LocalServerService.instance.handleExternalDelta(delta);
    });
  }

  // Load initial data
  settingsProvider.load();
  inventoryProvider.load();
  salesProvider.load();
  warehouseProvider.loadTransfers();
  patientProvider.load();
  opdProvider.loadAll();
  prescriptionProvider.load();
  templateProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: inventoryProvider),
        ChangeNotifierProvider.value(value: salesProvider),
        ChangeNotifierProvider.value(value: warehouseProvider),
        ChangeNotifierProvider.value(value: cartProvider),
        ChangeNotifierProvider.value(value: syncService),
        ChangeNotifierProvider.value(value: wsService),
        ChangeNotifierProvider.value(value: patientProvider),
        ChangeNotifierProvider.value(value: opdProvider),
        ChangeNotifierProvider.value(value: prescriptionProvider),
        ChangeNotifierProvider.value(value: templateProvider),
      ],
      child: const MediPossApp(),
    ),
  );
}

class MediPossApp extends StatefulWidget {
  const MediPossApp({super.key});

  @override
  State<MediPossApp> createState() => _MediPossAppState();
}

class _MediPossAppState extends State<MediPossApp> with WidgetsBindingObserver {
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (defaultTargetPlatform == TargetPlatform.windows && !_isExiting) {
      _isExiting = true;
      
      // Show "Syncing" dialog using GlobalNavigationService
      final context = GlobalNavigationService.navigatorKey.currentContext;
      if (context != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text(
                    'Syncing Data to Cloud...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please do not close the window.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      try {
        // Perform final cloud broadcast
        await LocalServerService.instance.broadcastAllToCloud();
      } catch (e) {
        debugPrint('Final Sync Failed: $e');
      }

      return AppExitResponse.exit;
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    return MaterialApp(
      navigatorKey: GlobalNavigationService.navigatorKey,
      title: 'MediPoss',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settingsProvider.themeMode,
      debugShowCheckedModeBanner: false,
      home: Consumer2<AuthProvider, SyncService>(
        builder: (ctx, auth, sync, _) {
          final isMobile = !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS);

          if (isMobile && !sync.isConnected) {
            return const ConnectionScreen();
          }
          if (!auth.isAuthenticated) {
            return const LoginScreen();
          }
          return const AppShell();
        },
      ),
    );
  }
}
