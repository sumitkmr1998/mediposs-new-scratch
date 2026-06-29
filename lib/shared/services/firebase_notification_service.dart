import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  if (message.data['event'] == 'new_patient') {
    final name = message.data['patientName'] ?? 'A new patient';
    final count = message.data['activeQueueCount'] ?? '0';
    
    await NotificationService.instance.showNotification(
      id: DateTime.now().millisecond,
      title: 'New Patient in Queue',
      body: '$name has been added. Active Queue: $count',
    );
  }
}

class FirebaseNotificationService {
  static final FirebaseNotificationService instance = FirebaseNotificationService._();
  FirebaseNotificationService._();

  Future<void> init() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await messaging.subscribeToTopic('opd_queue');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['event'] == 'new_patient') {
        final name = message.data['patientName'] ?? 'A new patient';
        final count = message.data['activeQueueCount'] ?? '0';
        
        NotificationService.instance.showNotification(
          id: DateTime.now().millisecond,
          title: 'New Patient in Queue',
          body: '$name has been added. Active Queue: $count',
        );
      }
    });
  }
}
