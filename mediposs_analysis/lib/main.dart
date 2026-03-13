import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'providers/hub_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Try to load .env, but don't fail if it's not present (useful for release)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('.env file not found, system will ask for API Key/IP manually.');
  }

  runApp(const MedipossAnalysisApp());
}

class MedipossAnalysisApp extends StatelessWidget {
  const MedipossAnalysisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => HubProvider())],
      child: MaterialApp(
        title: 'Mediposs Analysis & AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
