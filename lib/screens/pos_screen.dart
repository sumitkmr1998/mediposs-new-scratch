import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/medicine_dialog.dart';
import '../widgets/patient_dialogs.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/pos_windows.dart';
import 'android/pos_android.dart';

class PosScreen extends StatelessWidget {


  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return PosAndroid();
    }
    return PosWindows();
  }
}