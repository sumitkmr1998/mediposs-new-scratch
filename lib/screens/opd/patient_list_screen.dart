import 'package:flutter/material.dart';
import '../../widgets/patient_dialogs.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../windows/opd/patient_list_windows.dart';
import '../android/opd/patient_list_android.dart';

class PatientListScreen extends StatelessWidget {


  const PatientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return PatientListAndroid();
    }
    return PatientListWindows();
  }
}