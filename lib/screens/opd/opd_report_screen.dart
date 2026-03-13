import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../windows/opd/opd_report_windows.dart';
import '../android/opd/opd_report_android.dart';

class OpdReportScreen extends StatelessWidget {


  const OpdReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return OpdReportAndroid();
    }
    return OpdReportWindows();
  }
}