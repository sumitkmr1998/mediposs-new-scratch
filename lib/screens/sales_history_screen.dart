import 'package:flutter/material.dart';
import '../widgets/return_dialog.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/sales_history_windows.dart';
import 'android/sales_history_android.dart';

class SalesHistoryScreen extends StatelessWidget {


  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return SalesHistoryAndroid();
    }
    return SalesHistoryWindows();
  }
}