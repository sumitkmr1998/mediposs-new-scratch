import 'package:flutter/material.dart';
import 'dart:convert';
import '../../screens/android/opd/remote_camera_screen_android.dart';

class GlobalNavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static void handleRemoteCameraTrigger(Map<String, dynamic> msg) {
    debugPrint('GlobalNavigationService: Received remote_camera_trigger for ${msg['patientName']}');
    
    // Check if we are already on the camera screen to avoid duplicates
    bool isAlreadyOnCamera = false;
    navigatorKey.currentState?.popUntil((route) {
      if (route.settings.name == '/remote_camera') {
        isAlreadyOnCamera = true;
      }
      return true; 
    });

    if (!isAlreadyOnCamera) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/remote_camera'),
          builder: (_) => RemoteCameraScreenAndroid(
            patientUhid: msg['patientUhid'],
            patientName: msg['patientName'],
            hubIp: msg['hubIp'],
          ),
        ),
      );
    }
  }
}
