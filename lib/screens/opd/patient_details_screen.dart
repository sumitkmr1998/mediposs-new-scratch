import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../android/opd/patient_details_android.dart';
import '../windows/opd/patient_details_windows.dart';

class PatientDetailsScreen extends StatelessWidget {
  final int patientId;

  const PatientDetailsScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return PatientDetailsAndroid(patientId: patientId);
    }
    return PatientDetailsWindows(patientId: patientId);
  }
}
