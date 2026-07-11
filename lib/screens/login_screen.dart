import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'windows/login_windows.dart';
import 'android/login_android.dart';

class LoginScreen extends StatelessWidget {


  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return const LoginAndroid();
    }
    return const LoginWindows();
  }
}