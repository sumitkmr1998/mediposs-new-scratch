import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/connection_windows.dart';
import 'android/connection_android.dart';

class ConnectionScreen extends StatelessWidget {


  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return ConnectionAndroid();
    }
    return ConnectionWindows();
  }
}