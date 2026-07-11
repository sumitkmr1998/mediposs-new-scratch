import 'dart:io';
import 'package:flutter/material.dart';
import 'windows/app_shell_windows.dart';
import 'android/app_shell_android.dart';
import '../shared/services/objectbox_service.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = ObjectBoxService.instance.settings;
    if (Platform.isAndroid) {
      return const AppShellAndroid();
    }
    return const AppShellWindows();
  }
}
