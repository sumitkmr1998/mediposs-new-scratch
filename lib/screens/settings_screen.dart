import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/settings_windows.dart';
import 'android/settings_android.dart';

class SettingsScreen extends StatelessWidget {


  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return SettingsAndroid();
    }
    return SettingsWindows();
  }
}