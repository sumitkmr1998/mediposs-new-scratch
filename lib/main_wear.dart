import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'shared/services/objectbox_service.dart';
import 'shared/services/sync_service.dart';
import 'shared/providers/auth_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/sales_provider.dart';
import 'theme/app_theme.dart';
import 'screens/wear/wear_dashboard.dart';
import 'package:firebase_core/firebase_core.dart';
import 'shared/services/firebase_sync_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DB
  try {
    await ObjectBoxService.init();
  } catch (e) {
    debugPrint('Wear Main: ObjectBox initialization failed: $e');
  }

  // Initialize Firebase (optional/fallback sync)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseSyncService.init();
  } catch (e) {
    debugPrint('Wear Firebase Failed: $e');
  }

  final authProvider = AuthProvider();
  final settingsProvider = SettingsProvider();
  final salesProvider = SalesProvider();
  final syncService = SyncService();

  settingsProvider.load();
  salesProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: salesProvider),
        ChangeNotifierProvider.value(value: syncService),
      ],
      child: const MediPossWearApp(),
    ),
  );
}

class MediPossWearApp extends StatelessWidget {
  const MediPossWearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediPoss Wear',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const WearDashboard(),
    );
  }
}
