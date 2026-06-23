import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import '../providers/inventory_provider.dart';
import '../providers/sales_provider.dart';
import '../providers/patient_provider.dart';
import '../providers/opd_provider.dart';
import '../providers/prescription_provider.dart';
import '../providers/template_provider.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

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
    service.stopSelf();
  });

  debugPrint('BackgroundService: Started (standalone WebSocket, no ObjectBox)');

  String? hubIp;
  String? secret;
  WebSocketChannel? channel;
  bool connected = false;
  bool intentionalDisconnect = false;
  int reconnectAttempts = 0;
  Timer? heartbeatTimer;
  Timer? reconnectTimer;

  void notifyForeground(String event, dynamic data) {
    service.invoke('data_synced', {'event': event, 'data': data});
  }

  void updateNotification(String title, String content) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(title: title, content: content);
    }
  }

  Future<bool> testHubConnection(String address) async {
    try {
      final url = address.startsWith('http')
          ? Uri.parse('$address/health')
          : Uri.parse('http://$address:8080/health');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(url);
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain();
      client.close(force: false);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  late final void Function(String ip, String sec) doConnect;
  late final void Function() scheduleReconnect;

  scheduleReconnect = () {
    if (intentionalDisconnect || hubIp == null || secret == null) return;
    reconnectTimer?.cancel();

    final int delaySeconds = (2 << reconnectAttempts).clamp(2, 30);
    if (reconnectAttempts < 5) reconnectAttempts++;

    debugPrint('BackgroundService: Reconnecting in ${delaySeconds}s (attempt $reconnectAttempts)...');
    reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!intentionalDisconnect && hubIp != null && !connected) {
        doConnect(hubIp!, secret!);
      }
    });
  };

  doConnect = (String ip, String sec) {
    if (connected) return;
    try {
      Uri uri;
      if (ip.startsWith('http')) {
        final base = Uri.parse(ip);
        final scheme = base.scheme == 'https' ? 'wss' : 'ws';
        String path = base.path;
        if (!path.endsWith('/')) path += '/';
        path += 'ws/updates';
        uri = base.replace(scheme: scheme, path: path, queryParameters: {'secret': sec});
      } else {
        uri = Uri.parse('ws://$ip:8080/ws/updates?secret=$sec');
      }

      debugPrint('BackgroundService: WebSocket connecting to $uri');
      channel = WebSocketChannel.connect(uri);
      connected = true;
      reconnectAttempts = 0;

      channel!.stream.listen(
        (data) {
          try {
            final Map<String, dynamic> msg;
            if (data is Map) {
              msg = Map<String, dynamic>.from(data);
            } else {
              String dataStr;
              if (data is String) {
                dataStr = data;
              } else if (data is List<int>) {
                dataStr = utf8.decode(data);
              } else {
                dataStr = data.toString();
              }
              final decoded = jsonDecode(dataStr);
              if (decoded is Map) {
                msg = Map<String, dynamic>.from(decoded);
              } else {
                return;
              }
            }

            debugPrint('BackgroundService: WS event: ${msg['event']}');
            notifyForeground(msg['event'], msg);
          } catch (e) {
            debugPrint('BackgroundService: Error parsing message: $e');
          }
        },
        onDone: () {
          connected = false;
          debugPrint('BackgroundService: WebSocket closed.');
          updateNotification("MediPoss Disconnected", "Hub connection lost. Reconnecting...");
          if (!intentionalDisconnect && hubIp != null) {
            scheduleReconnect();
          }
        },
        onError: (e) {
          connected = false;
          debugPrint('BackgroundService: WebSocket error: $e');
          updateNotification("MediPoss Disconnected", "Connection error. Reconnecting...");
          if (!intentionalDisconnect && hubIp != null) {
            scheduleReconnect();
          }
        },
      );

      updateNotification("MediPoss Connected", "Listening for updates from Hub");
    } catch (e) {
      connected = false;
      debugPrint('BackgroundService: Connect failed: $e');
      if (!intentionalDisconnect && hubIp != null) {
        scheduleReconnect();
      }
    }
  };

  void startHeartbeat() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (intentionalDisconnect || hubIp == null) {
        timer.cancel();
        return;
      }
      final reachable = await testHubConnection(hubIp!);
      if (!reachable && connected) {
        debugPrint('BackgroundService: Heartbeat failed! Reconnecting...');
        connected = false;
        channel?.sink.close();
        updateNotification("MediPoss Disconnected", "Hub unreachable. Reconnecting...");
        scheduleReconnect();
      }
    });
  }

  // Listen for config updates from foreground (hubIp + secret)
  service.on('updateConfig').listen((event) {
    if (event == null) return;
    final newHubIp = event['hubIp'] as String?;
    final newSecret = event['secret'] as String?;
    if (newHubIp != null && newSecret != null) {
      hubIp = newHubIp;
      secret = newSecret;
      debugPrint('BackgroundService: Config updated - hubIp=$hubIp');
      intentionalDisconnect = false;
      if (!connected) {
        doConnect(hubIp!, secret!);
        startHeartbeat();
      }
    }
  });

  // Also listen for explicit connect/disconnect commands
  service.on('connectHub').listen((event) {
    if (event == null) return;
    final ip = event['hubIp'] as String?;
    final sec = event['secret'] as String?;
    if (ip != null && sec != null) {
      hubIp = ip;
      secret = sec;
      intentionalDisconnect = false;
      connected = false;
      channel?.sink.close();
      doConnect(hubIp!, secret!);
      startHeartbeat();
    }
  });

  service.on('disconnectHub').listen((event) {
    intentionalDisconnect = true;
    heartbeatTimer?.cancel();
    reconnectTimer?.cancel();
    channel?.sink.close();
    connected = false;
    hubIp = null;
    secret = null;
    updateNotification("MediPoss Paused", "Disconnected from Hub");
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
