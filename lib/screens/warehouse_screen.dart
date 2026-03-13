import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/warehouse_windows.dart';
import 'android/warehouse_android.dart';

class WarehouseScreen extends StatelessWidget {


  const WarehouseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return WarehouseAndroid();
    }
    return WarehouseWindows();
  }
}