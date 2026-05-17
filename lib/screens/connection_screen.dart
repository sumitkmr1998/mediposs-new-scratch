import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/connection_windows.dart';
import 'android/connection_android.dart';
import '../shared/services/objectbox_service.dart';

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = ObjectBoxService.instance.settings;
    if (Platform.isAndroid) {
      return const ConnectionAndroid();
    }
    return const ConnectionWindows();
  }
}