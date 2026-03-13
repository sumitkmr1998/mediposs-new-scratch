import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../windows/opd/doctor_list_windows.dart';
import '../android/opd/doctor_list_android.dart';

class DoctorListScreen extends StatelessWidget {


  const DoctorListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return DoctorListAndroid();
    }
    return DoctorListWindows();
  }
}