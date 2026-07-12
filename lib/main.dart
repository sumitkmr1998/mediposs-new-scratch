import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'shared/services/objectbox_service.dart';
import 'shared/services/sync_service.dart';
import 'shared/services/sync/sync_facade.dart';
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
import 'shared/providers/procedure_provider.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/app_shell.dart';
import 'screens/connection_screen.dart';
import 'package:flutter/foundation.dart';
import 'shared/services/local_server_service.dart';
import 'shared/services/discovery_service.dart';
import 'shared/services/global_navigation_service.dart';
import 'shared/providers/navigation_provider.dart';
import 'shared/services/sync_queue_service.dart';
import 'shared/models/medicine.dart';
import 'objectbox.g.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:firebase_core/firebase_core.dart';
import 'shared/services/firebase_sync_service.dart';
import 'shared/services/cloudflare_service.dart';
import 'firebase_options.dart';

import 'shared/services/background_sync_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'shared/services/firebase_notification_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final forceTerminal = args.contains('--terminal') || const bool.fromEnvironment('terminal', defaultValue: false);
  
  // 0. On Android, if background service is already running, we MUST stop it 
  // to release the ObjectBox lock before the main isolate can open it.
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        debugPrint('Main: Background service is already running. Stopping to release DB lock...');
        service.invoke('stopService');
        // Give it time to close the store
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    } catch (e) {
      debugPrint('Main: Error stopping background service: $e');
    }
  }

  // 1. Initialize DB FIRST - Most critical for both UI and background
  try {
    debugPrint('Main: Initializing ObjectBox (forceTerminal=$forceTerminal)...');
    await ObjectBoxService.init(forceTerminal: forceTerminal);
    debugPrint('Main: ObjectBox initialized.');
  } catch (e) {
    debugPrint('Main: ObjectBox initialization failed: $e');
  }

  // 2. Initialize Background Service (Android)
  // We start this AFTER DB init so main isolate has the handle
  if (defaultTargetPlatform == TargetPlatform.android) {
    debugPrint('Main: Initializing Background Service...');
    await initializeBackgroundService();
    debugPrint('Main: Background Service initialized.');
  }

  // 3. Initialize Firebase
  try {
    debugPrint('Main: Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseSyncService.init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await FirebaseNotificationService.instance.init();
    }
  } catch (e) {
    debugPrint('Firebase Initialization Failed: $e');
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

  // Listen to SyncService changes to reload local providers on sync completion
  bool wasSyncing = false;
  syncService.addListener(() {
    final isSyncing = syncService.isSyncing;
    if (wasSyncing && !isSyncing) {
      debugPrint('Main: SyncService completed sync. Reloading providers...');
      inventoryProvider.load();
      salesProvider.load();
      patientProvider.load();
      opdProvider.loadAll();
      prescriptionProvider.load();
      templateProvider.load();
    }
    wasSyncing = isSyncing;
  });

  // Global listener for real-time data sync (Mobile Only)
  setupForegroundSyncListeners(
      inventoryProvider,
      salesProvider,
      patientProvider,
      opdProvider,
      prescriptionProvider,
      templateProvider);

  wsService.eventStream.listen((msg) {
    final event = msg['event'];
    debugPrint('Mobile WebSocket Event: $event');
    if (event == 'remote_camera_trigger') {
      GlobalNavigationService.handleRemoteCameraTrigger(msg);
    } else if (event == 'sync_received' || 
               event == 'medicines_updated' || 
               event == 'sales_updated' ||
               event == 'patients_updated' ||
               event == 'appointments_updated' ||
               event == 'audit_logs_updated') {
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
    } else if (event == 'patient_deleted') {
      final uhid = msg['uhid'];
      if (uhid != null) {
        final box = ObjectBoxService.instance.patientBox;
        final p = box.query(Patient_.uhid.equals(uhid)).build().findFirst();
        if (p != null) {
          box.remove(p.id);
          patientProvider.load();
        }
      }
    } else if (event == 'medicine_deleted') {
      final barcode = msg['barcode'];
      final name = msg['name'];
      if (barcode != null || name != null) {
        final box = ObjectBoxService.instance.medicineBox;
        Condition<Medicine>? cond;
        if (barcode != null) cond = Medicine_.barcode.equals(barcode);
        if (name != null) {
          final nameCond = Medicine_.name.equals(name);
          cond = cond == null ? nameCond : cond.and(nameCond);
        }
        if (cond != null) {
          final m = box.query(cond).build().findFirst();
          if (m != null) {
            box.remove(m.id);
            inventoryProvider.load();
          }
        }
      }
    } else if (event == 'sale_deleted') {
      final invoiceNo = msg['invoiceNo'];
      if (invoiceNo != null) {
        final box = ObjectBoxService.instance.saleBox;
        final s = box.query(Sale_.invoiceNo.equals(invoiceNo)).build().findFirst();
        if (s != null) {
          box.remove(s.id);
          salesProvider.load();
        }
      }
    }
  });

  // Try to auto-connect to a saved Hub IP so companion app skips connection screen
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  final isClient = isMobile || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);

  if (isClient) {
    final connected = await syncService.tryAutoConnect().timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (connected && syncService.hubIp != null) {
      wsService.connect(syncService.hubIp!, syncService.secret);
    }
  } else if (Platform.isWindows) {
    // Start Hub server immediately on Windows launch
    await LocalServerService.instance.start();
    await DiscoveryService.startAdvertising(
        ObjectBoxService.instance.settings.serverPort,
        ObjectBoxService.instance.settings.shopId);
    
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
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: inventoryProvider),
        ChangeNotifierProvider.value(value: salesProvider),
        ChangeNotifierProvider.value(value: warehouseProvider),
        ChangeNotifierProvider.value(value: cartProvider),
        ChangeNotifierProvider.value(value: syncService),
        ChangeNotifierProvider.value(value: SyncFacade.instance),
        ChangeNotifierProvider.value(value: wsService),
        ChangeNotifierProvider.value(value: patientProvider),
        ChangeNotifierProvider.value(value: opdProvider),
        ChangeNotifierProvider.value(value: prescriptionProvider),
        ChangeNotifierProvider.value(value: templateProvider),
        ChangeNotifierProvider(create: (_) => ProcedureProvider()),
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App Resumed: Refreshing sync...');
      final syncService = context.read<SyncService>();
      final wsService = context.read<WebSocketService>();
      
      // Re-trigger sync and check WS
      syncService.syncAll().then((_) {
        context.read<InventoryProvider>().load();
        context.read<SalesProvider>().load();
        context.read<PatientProvider>().load();
        context.read<OpdProvider>().loadAll();
        context.read<PrescriptionProvider>().load();
        context.read<TemplateProvider>().load();
      });

      if (!wsService.connected && syncService.hubIp != null) {
        wsService.connect(syncService.hubIp!, syncService.secret);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final cartProvider = context.watch<CartProvider>();

    return MaterialApp(
      navigatorKey: GlobalNavigationService.navigatorKey,
      title: 'MediPoss',
      theme: AppTheme.themeFor(
        isClinical: cartProvider.isClinicalDispense,
        isReturn: cartProvider.isReturnMode,
        brightness: Brightness.light,
      ),
      darkTheme: AppTheme.themeFor(
        isClinical: cartProvider.isClinicalDispense,
        isReturn: cartProvider.isReturnMode,
        brightness: Brightness.dark,
      ),
      themeMode: settingsProvider.themeMode,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'GB'),
        Locale('en', 'US'),
        Locale('en', 'IN'),
      ],
      home: Consumer2<AuthProvider, SyncService>(
        builder: (ctx, auth, sync, _) {
          final isMobileDevice = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
          final isWindowsClient = defaultTargetPlatform == TargetPlatform.windows && ObjectBoxService.instance.settings.isWindowsClient;
          final isClient = isMobileDevice || isWindowsClient;

          if (isClient && !sync.isConnected) {
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
