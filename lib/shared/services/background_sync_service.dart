import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../objectbox.g.dart';
import '../models/patient.dart';
import '../models/medicine.dart';
import '../models/sale.dart';
import 'package:flutter/foundation.dart';
import '../providers/inventory_provider.dart';
import '../providers/sales_provider.dart';
import '../providers/patient_provider.dart';
import '../providers/opd_provider.dart';
import '../providers/prescription_provider.dart';
import '../providers/template_provider.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Create notification channel for Android 8.0+
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'sync_channel',
    'MediPoss Sync Service',
    description: 'Running background synchronization with Hub',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'sync_channel',
      initialNotificationTitle: 'MediPoss Background Sync',
      initialNotificationContent: 'Ready to sync data from Hub',
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) async {
    try {
      await ObjectBoxService.instance.close();
    } catch (_) {}
    service.stopSelf();
  });

  // Initialize DB in this isolate
  // We add a small delay to avoid race conditions with the main isolate during boot
  await Future.delayed(const Duration(seconds: 1));
  
  try {
    debugPrint('BackgroundService: Initializing ObjectBox...');
    await ObjectBoxService.init();
    debugPrint('BackgroundService: ObjectBox initialized.');
  } catch (e) {
    debugPrint('BackgroundService: DB Init failed: $e');
    // If it fails, we might be in a lock situation. 
    // We'll retry once after a longer delay.
    await Future.delayed(const Duration(seconds: 5));
    try {
      await ObjectBoxService.init();
    } catch (e2) {
      debugPrint('BackgroundService: DB Init retry failed: $e2');
    }
  }
  
  final syncService = SyncService();
  final wsService = WebSocketService();

  // Helper to notify foreground app
  void notifyForeground(String event, dynamic data) {
    service.invoke('data_synced', {'event': event, 'data': data});
  }

  // Real-time listener logic (duplicated from main.dart but for background)
  wsService.eventStream.listen((msg) async {
    if (!ObjectBoxService.isInitialized) return;
    final event = msg['event'];
    debugPrint('Background WebSocket Event: $event');
    
    if (event == 'sync_received' || 
        event == 'medicines_updated' || 
        event == 'sales_updated' ||
        event == 'patients_updated' ||
        event == 'appointments_updated') {
      
      await syncService.syncAll();
      notifyForeground(event, msg);
      
    } else if (event == 'settings_updated') {
      await syncService.pullSettings();
      notifyForeground(event, msg);
    } else if (event == 'users_updated') {
      await syncService.pullUsers();
      notifyForeground(event, msg);
    } else if (event == 'patient_deleted') {
      final uhid = msg['uhid'];
      if (uhid != null) {
        final box = ObjectBoxService.instance.patientBox;
        final p = box.query(Patient_.uhid.equals(uhid)).build().findFirst();
        if (p != null) {
          box.remove(p.id);
          notifyForeground(event, msg);
        }
      }
    } else if (event == 'medicine_deleted') {
      final barcode = msg['barcode'];
      final name = msg['name'];
      if (barcode != null || name != null) {
        final box = ObjectBoxService.instance.medicineBox;
        Condition<Medicine>? cond;
        if (barcode != null) cond = Medicine_.barcode.equals(barcode);
        if (name != null) {
          final nameCond = Medicine_.name.equals(name);
          cond = (cond == null) ? nameCond : cond.and(nameCond);
        }
        
        if (cond != null) {
          final m = box.query(cond).build().findFirst();
          if (m != null) {
            box.remove(m.id);
            notifyForeground(event, msg);
          }
        }
      }
    } else if (event == 'sale_deleted') {
      final inv = msg['invoiceNo'];
      if (inv != null) {
        final box = ObjectBoxService.instance.saleBox;
        final s = box.query(Sale_.invoiceNo.equals(inv)).build().findFirst();
        if (s != null) {
          box.remove(s.id);
          notifyForeground(event, msg);
        }
      }
    }
  });

  // Connection Management
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (!ObjectBoxService.isInitialized) return;
    if (wsService.connected) return;

    final connected = await syncService.tryAutoConnect();
    if (connected && syncService.hubIp != null) {
      wsService.connect(syncService.hubIp!, syncService.secret);
      
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "MediPoss Connected",
          content: "Listening for updates from Hub (${syncService.hubIp})",
        );
      }
    } else {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "MediPoss Sync Paused",
          content: "Hub unreachable. Waiting for connection...",
        );
      }
    }
  });
}

void setupForegroundSyncListeners(
  InventoryProvider inventoryProvider,
  SalesProvider salesProvider,
  PatientProvider patientProvider,
  OpdProvider opdProvider,
  PrescriptionProvider prescriptionProvider,
  TemplateProvider templateProvider,
) {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) return;

  FlutterBackgroundService().on('data_synced').listen((event) {
    debugPrint('Foreground: Received sync notification from Background Service');
    inventoryProvider.load();
    salesProvider.load();
    patientProvider.load();
    opdProvider.loadAll();
    prescriptionProvider.load();
    templateProvider.load();
  });
}
