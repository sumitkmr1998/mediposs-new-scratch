import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/dashboard_windows.dart';
import 'android/dashboard_android.dart';

class DashboardScreen extends StatelessWidget {


  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return const DashboardAndroid();
    }
    return const DashboardWindows();
  }
}