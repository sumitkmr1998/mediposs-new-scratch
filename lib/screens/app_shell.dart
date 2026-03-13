import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'windows/app_shell_windows.dart';
import 'android/app_shell_android.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return AppShellAndroid();
    }
    return AppShellWindows();
  }
}
