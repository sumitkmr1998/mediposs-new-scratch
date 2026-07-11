import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'windows/pos_windows.dart';
import 'android/pos_android.dart';

class PosScreen extends StatelessWidget {


  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return const PosAndroid();
    }
    return const PosWindows();
  }
}