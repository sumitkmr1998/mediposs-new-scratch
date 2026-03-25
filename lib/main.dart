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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize DB
  await ObjectBoxService.init();

  // 2. Setup Base Providers
  final authProvider = AuthProvider();
  final inventoryProvider = InventoryProvider();
  final salesProvider = SalesProvider();
  final warehouseProvider = WarehouseProvider(inventoryProvider);
  final prescriptionProvider = PrescriptionProvider();

  // 3. OPD Providers
  final patientProvider = PatientProvider();
  final opdProvider = OpdProvider();
  final templateProvider = TemplateProvider();

  // 4. Cart Provider (Depends on inventory, sales, prescription, and opd)
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
    await syncService.tryAutoConnect();
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
      title: 'MediPoss',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settingsProvider.themeMode,
      debugShowCheckedModeBanner: false,
      home: Consumer2<AuthProvider, SyncService>(
        builder: (ctx, auth, sync, _) {
          // If we are a mobile app (companion), we must connect to a Hub first.
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
