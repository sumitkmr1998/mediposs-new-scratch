import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_options.dart';
import 'firebase_sync_service.dart';
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
      autoStartOnBoot: true,
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

  Timer? dbRetryTimer;

  Future<void> startServiceLogics() async {
    // Initialize notifications in background isolate
    try {
      await NotificationService.instance.init();
    } catch (e) {
      debugPrint('BackgroundService: NotificationService Init failed: $e');
    }

    // Initialize Firebase in background isolate
    try {
      debugPrint('BackgroundService: Initializing Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseSyncService.init();
      debugPrint('BackgroundService: Firebase initialized.');
    } catch (e) {
      debugPrint('BackgroundService: Firebase Init failed: $e');
    }

    // Start Firestore Notification Listener if enabled
    try {
      final settings = ObjectBoxService.instance.settings;
      if (settings.firebaseEnabled) {
        final shopId = settings.shopId.isNotEmpty
            ? settings.shopId
            : settings.storeName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
        
        final actualShopId = shopId.isNotEmpty ? shopId : 'default_shop';
        debugPrint('BackgroundService: Starting Firestore Notification listener for shop: $actualShopId');
        
        final Set<String> processedIds = {};
        bool isInitialLoad = true;

        FirebaseFirestore.instance
            .collection('shops')
            .doc(actualShopId)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .limit(10)
            .snapshots()
            .listen((snapshot) {
              if (isInitialLoad) {
                for (var doc in snapshot.docs) {
                  processedIds.add(doc.id);
                }
                isInitialLoad = false;
                debugPrint('BackgroundService: Firestore listener initialized with ${processedIds.length} existing notifications.');
                return;
              }

              for (var doc in snapshot.docs) {
                if (!processedIds.contains(doc.id)) {
                  processedIds.add(doc.id);
                  
                  final data = doc.data();
                  if (data != null && data['event'] == 'new_patient') {
                    final payload = data['data'] as Map<String, dynamic>?;
                    if (payload != null) {
                      final patientName = payload['patientName'] ?? 'A patient';
                      final activeQueueCount = payload['activeQueueCount'] ?? 0;
                      NotificationService.instance.showNotification(
                        id: DateTime.now().millisecond,
                        title: 'New Patient in Queue',
                        body: activeQueueCount > 0
                            ? '$patientName has been added. Active Queue: $activeQueueCount'
                            : '$patientName has been added.',
                      );
                    }
                  }
                }
              }
            }, onError: (err) {
              debugPrint('BackgroundService: Firestore Notification listener error: $err');
            });
      }
    } catch (e) {
      debugPrint('BackgroundService: Failed to setup Firestore Notification listener: $e');
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

  void tryInitializeDB() async {
    try {
      debugPrint('BackgroundService: Attempting database initialization retry...');
      await ObjectBoxService.init();
      debugPrint('BackgroundService: Database initialized successfully on retry!');
      dbRetryTimer?.cancel();
      await startServiceLogics();
    } catch (e) {
      debugPrint('BackgroundService: Database initialization failed (lock active): $e');
    }
  }

  // Initial attempt after a short delay
  await Future.delayed(const Duration(seconds: 1));
  try {
    await ObjectBoxService.init();
    debugPrint('BackgroundService: Database initialized on startup.');
    await startServiceLogics();
  } catch (e) {
    debugPrint('BackgroundService: Database locked on startup. Scheduling retry loop: $e');
    // Start periodic retry timer every 10 seconds
    dbRetryTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      tryInitializeDB();
    });
  }
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
