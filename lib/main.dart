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
import 'package:flutter_displaymode/flutter_displaymode.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize DB FIRST (so settings are available)
  await ObjectBoxService.init();

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

  // Try to auto-connect to a saved Hub IP so companion app skips connection screen
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (isMobile) {
    final connected = await syncService.tryAutoConnect();
    if (connected && syncService.hubIp != null) {
      wsService.connect(syncService.hubIp!);
      // Global listener for automatic pop-ups
      wsService.eventStream.listen((msg) {
        if (msg['event'] == 'remote_camera_trigger') {
          GlobalNavigationService.handleRemoteCameraTrigger(msg);
        }
      });
    }
  } else if (Platform.isWindows) {
    // Start Hub server immediately on Windows launch
    await LocalServerService.instance.start();
    await DiscoveryService.startAdvertising(
        ObjectBoxService.instance.settings.serverPort);
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

class MediPossApp extends StatelessWidget {
  const MediPossApp({super.key});

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
