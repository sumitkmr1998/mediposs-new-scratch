import 'package:flutter/material.dart';
import '../../shared/models/appointment.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../windows/opd/prescription_windows.dart';
import '../android/opd/prescription_android.dart';

class PrescriptionScreen extends StatelessWidget {
  final Appointment appointment;

  const PrescriptionScreen({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return PrescriptionAndroid(appointment: appointment);
    }
    return PrescriptionWindows(appointment: appointment);
  }
}