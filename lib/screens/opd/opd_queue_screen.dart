import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../windows/opd/opd_queue_windows.dart';
import '../android/opd/opd_queue_android.dart';

class OpdQueueScreen extends StatelessWidget {


  const OpdQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return const OpdQueueAndroid();
    }
    return const OpdQueueWindows();
  }
}