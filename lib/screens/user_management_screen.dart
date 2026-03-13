import 'package:flutter/material.dart';
import '../widgets/user_form_dialog.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows/user_management_windows.dart';
import 'android/user_management_android.dart';

class UserManagementScreen extends StatelessWidget {


  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return UserManagementAndroid();
    }
    return UserManagementWindows();
  }
}