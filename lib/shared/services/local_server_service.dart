import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../services/firebase_sync_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:path_provider/path_provider.dart';
import '../services/objectbox_service.dart';
import '../models/medicine.dart';
import '../models/app_user.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../models/patient_image.dart';
import '../models/prescription_template.dart';
import '../models/appointment.dart';
import '../models/prescription.dart';
import '../models/doctor.dart';
import '../models/stock_transfer.dart';
import '../models/procedure.dart';
import 'package:objectbox/objectbox.dart';
import '../../objectbox.g.dart';
import 'package:flutter/foundation.dart';

class LocalServerService {
  static LocalServerService? _instance;
  static LocalServerService get instance =>
      _instance ??= LocalServerService._();

  LocalServerService._();

  HttpServer? _server;
  final Set<WebSocketChannel> _wsClients = {};
  bool get isRunning => _server != null;

  // Stream that fires when Android pushes data to the Hub
  // AppShell listens to this on Windows to trigger provider reloads
  final StreamController<String> _incomingDataController =
      StreamController<String>.broadcast();
  Stream<String> get incomingDataStream => _incomingDataController.stream;

  String get _jwtSecret => ObjectBoxService.instance.settings.jwtSecret;
  int get _port => ObjectBoxService.instance.settings.serverPort;

  Future<void> start() async {
    if (_server != null) return;

    final router = Router();

    // ------ Public endpoints ------
    router.get('/health', _healthHandler);
    router.post('/api/auth/login', _loginHandler);
    router.get('/api/users', _usersGetHandler);
    router.get('/download-apk', _apkDownloadHandler);

    // ------ Protected endpoints ------
    router.get('/api/medicines', _withAuth(_medicinesGetHandler));
    router.post('/api/medicines/push', _withAuth(_medicinesPushHandler));
    router.post('/api/medicines/sync', _withAuth(_medicinesSyncHandler));
    router.get('/api/transfers', _withAuth(_transfersGetHandler));
    router.post('/api/transfers/push', _withAuth(_transfersPushHandler));
    router.get('/api/sales', _withAuth(_salesGetHandler));
    router.post('/api/sales/push', _withAuth(_salesPushHandler));
    router.get('/api/patients', _withAuth(_patientsGetHandler));
    router.post('/api/patients/push', _withAuth(_patientsPushHandler));
    router.get('/api/appointments', _withAuth(_appointmentsGetHandler));
    router.post('/api/appointments/push', _withAuth(_appointmentsPushHandler));
    router.get('/api/doctors', _withAuth(_doctorsGetHandler));
    router.post('/api/doctors/push', _doctorsPushHandler);
    router.post('/api/doctors/delete', _doctorsDeleteHandler);
    router.post('/api/patients/delete', _patientsDeleteHandler);
    router.post('/api/medicines/delete', _medicinesDeleteHandler);
    router.post('/api/prescriptions/delete', _prescriptionsDeleteHandler);
    router.get('/api/prescriptions', _prescriptionsGetHandler);
    router.post(
        '/api/prescriptions/push', _withAuth(_prescriptionsPushHandler));
    router.get('/api/templates', _withAuth(_templatesGetHandler));
    router.post('/api/templates/push', _withAuth(_templatesPushHandler));
    router.get('/api/patient-photos', _withAuth(_patientPhotosGetHandler));
    router.post(
        '/api/patient-photos/push', _withAuth(_patientPhotosPushHandler));
    router.post(
        '/api/prescriptions/photos/push', _withAuth(_prescriptionPhotosPushHandler));
    router.post('/api/settings/push', _withAuth(_settingsPushHandler));
    router.post('/api/settings', _withAuth(_settingsGetHandler)); // Allow GET settings via POST for some clients
    router.get('/api/settings', _withAuth(_settingsGetHandler));
    router.post('/api/users/push', _withAuth(_usersPushHandler));
    router.get('/api/procedures', _withAuth(_proceduresGetHandler));
    router.post('/api/procedures/push', _withAuth(_proceduresPushHandler));
    router.post('/api/procedures/delete', _withAuth(_proceduresDeleteHandler));
    router.post('/api/sync', _withAuth(_syncHandler));

    // Deletion Endpoints
    router.post('/api/sales/delete', _withAuth(_salesDeleteHandler));
    router.post('/api/templates/delete', _withAuth(_templatesDeleteHandler));
    router.post(
        '/api/patients/photos/delete', _withAuth(_patientPhotosDeleteHandler));

    // ------ WebSocket ------
    router.get('/ws/updates', webSocketHandler(_onWsConnect, pingInterval: const Duration(seconds: 15)));

    final pipeline = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_gzipMiddleware())
        .addMiddleware(_secretMiddleware())
        .addHandler(router.call);

    _server = await io.serve(pipeline, InternetAddress.anyIPv4, _port);
    
    // One-time migration for legacy records that lack sync metadata
    _migrateSyncMetadata();

    // Initial broadcast to Cloud for companion app fallback
    broadcastAllToCloud();
    // Periodic refresh every 10 minutes to keep Cloud collections fresh
    Timer.periodic(const Duration(minutes: 10), (_) => broadcastAllToCloud());
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // Broadcast a JSON message to all connected WS clients
  void broadcast(Map<String, dynamic> message) {
    if (!isRunning) return;
    final data = jsonEncode(message);
    debugPrint('LocalServerService: Broadcasting ${message['event']} to ${_wsClients.length} clients');
    for (final client in _wsClients.toList()) {
      try {
        client.sink.add(data);
      } catch (_) {
        _wsClients.remove(client);
      }
    }
  }

  Middleware _secretMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        // Always allow health check and APK download for easier distribution
        if (request.url.path == 'health' || request.url.path == 'download-apk') {
          return innerHandler(request);
        }

        final secret = request.headers['X-MediPass-Secret'] ?? request.url.queryParameters['secret'];
        final hubSecret = ObjectBoxService.instance.settings.jwtSecret;

        if (secret != hubSecret) {
          debugPrint('Hub: Blocked request with invalid secret from ${request.context['shelf.io.connection_info']}');
          return Response.forbidden(
            jsonEncode({'error': 'Unauthorized: Invalid Hub Secret'}),
            headers: {'content-type': 'application/json'},
          );
        }

        return innerHandler(request);
      };
    };
  }

  void _onWsConnect(WebSocketChannel channel) {
    debugPrint('LocalServerService: New WebSocket client connected! Total clients: ${_wsClients.length + 1}');
    _wsClients.add(channel);
    channel.stream.listen(
      (_) {},
      onDone: () {
        _wsClients.remove(channel);
        debugPrint('LocalServerService: WebSocket client disconnected. Total clients: ${_wsClients.length}');
      },
      onError: (_) {
        _wsClients.remove(channel);
        debugPrint('LocalServerService: WebSocket client error. Total clients: ${_wsClients.length}');
      },
    );
  }

  // ---- Handlers ----

  Response _healthHandler(Request req) => Response.ok(
        jsonEncode(
            {'status': 'ok', 'timestamp': DateTime.now().toIso8601String()}),
        headers: {'content-type': 'application/json'},
      );

  Future<Response> _loginHandler(Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final pin = body['pin']?.toString() ?? '';
    final name = body['name']?.toString() ?? '';

    final users = ObjectBoxService.instance.userBox.getAll();
    debugPrint(
        'Hub: login attempt for user "$name" with PIN $pin. Total users in DB: ${users.length}');
    final user = users.cast<AppUser?>().firstWhere(
          (u) => u!.name == name && u.pin == pin && u.isActive,
          orElse: () => null,
        );

    if (user == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Invalid PIN'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final jwt = JWT({'userId': user.id, 'role': user.role, 'name': user.name});
    final token = jwt.sign(SecretKey(_jwtSecret));

    return Response.ok(
      jsonEncode({
        'token': token, 
        'role': user.role, 
        'name': user.name,
        'permissions': user.toJson(), // Full profile for immediate client-side auth refresh
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _usersGetHandler(Request req) {
    final users = ObjectBoxService.instance.userBox.getAll();
    debugPrint('Hub: Serving ${users.length} total users to client.');
    // Only return public info, never the PIN.
    final json = users.where((u) => u.isActive).map((u) {
      final map = u.toJson();
      map['pin'] = 'xxxx'; // Mask PIN for security during general pull
      debugPrint('Hub User: id=${u.id}, name=${u.name}, role=${u.role}');
      return map;
    }).toList();

    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _proceduresGetHandler(Request req) {
    final list = ObjectBoxService.instance.procedureBox.getAll();
    return Response.ok(
      jsonEncode(
          {'data': list.map((e) => e.toJson()).toList(), 'count': list.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _proceduresPushHandler(Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = data['name'] as String? ?? '';
      if (name.isEmpty) return Response.badRequest();

      final box = ObjectBoxService.instance.procedureBox;
      final existing =
          box.query(Procedure_.name.equals(name)).build().findFirst();

      final p = Procedure.fromJson(data);
      if (existing != null) {
        p.id = existing.id;
      } else {
        p.id = 0;
      }

      box.put(p);
      broadcast({'event': 'procedures_updated'});
      _incomingDataController.add('procedures');

      return Response.ok(jsonEncode({'success': true}));
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}));
    }
  }

  Future<Response> _proceduresDeleteHandler(Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final id = data['id'] as int? ?? 0;
      final name = data['name'] as String? ?? '';

      final box = ObjectBoxService.instance.procedureBox;
      Procedure? target;
      if (id > 0) {
        target = box.get(id);
      } else if (name.isNotEmpty) {
        target = box.query(Procedure_.name.equals(name)).build().findFirst();
      }

      if (target != null) {
        box.remove(target.id);
        broadcast({'event': 'procedures_updated'});
        _incomingDataController.add('procedures');
      }
      return Response.ok(jsonEncode({'success': true}));
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}));
    }
  }

  Future<Response> _apkDownloadHandler(Request req) async {
    final apkPath = 'build/app/outputs/flutter-apk/app-release.apk';
    final file = File(apkPath);
    if (!await file.exists()) {
      return Response.notFound('APK not found on Hub. Please compile it first.');
    }

    final size = await file.length();
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'application/vnd.android.package-archive',
        'content-length': size.toString(),
        'content-disposition': 'attachment; filename="MediPoss_v1.2.apk"',
      },
    );
  }

  Future<Response> _usersPushHandler(Request req) async {
    try {
      final item = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final box = ObjectBoxService.instance.userBox;
      final name = item['name'] as String? ?? '';
      
      if (name.isEmpty) {
        return Response.badRequest(body: jsonEncode({'error': 'Name is required'}));
      }

      final existing = box.query(AppUser_.name.equals(name)).build().findFirst();
      if (existing != null) {
        final u = AppUser.fromJson(item);
        u.id = existing.id;
        box.put(u);
      } else {
        final u = AppUser.fromJson(item);
        u.id = 0;
        box.put(u);
      }

      broadcast({'event': 'users_updated'});
      _incomingDataController.add('users');
      return Response.ok(jsonEncode({'success': true}));
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  Response _settingsGetHandler(Request req) {
    final settings = ObjectBoxService.instance.settings;
    return Response.ok(
      jsonEncode(settings.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _settingsPushHandler(Request req) async {
    try {
      final item = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final box = ObjectBoxService.instance.settingsBox;
      final current = ObjectBoxService.instance.settings;
      
      final updated = AppSettings.fromJson(item);
      updated.id = current.id;
      // Do not overwrite hub-specific or device-specific fields if pushed from companion
      updated.isWindowsClient = current.isWindowsClient;
      updated.deviceId = current.deviceId;
      updated.hubIp = current.hubIp; 
      updated.serverPort = current.serverPort;
      updated.jwtSecret = current.jwtSecret;
      updated.autoLoginPin = current.autoLoginPin;
      updated.autoLoginName = current.autoLoginName;
      updated.defaultPrinterName = current.defaultPrinterName;
      updated.autoPrintReceipt = current.autoPrintReceipt;
      updated.receiptPaperSize = current.receiptPaperSize;

      box.put(updated);
      
      broadcast({'event': 'settings_updated'});
      _incomingDataController.add('settings');
      return Response.ok(jsonEncode({'success': true}));
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  Response _medicinesGetHandler(Request req) {
    final sinceStr = req.url.queryParameters['since'];
    final since = DateTime.tryParse(sinceStr ?? '') ?? DateTime(2000);

    final box = ObjectBoxService.instance.medicineBox;
    final medicines = box.query(Medicine_.updatedAt.greaterThan(since.millisecondsSinceEpoch)).build().find();
    
    final json = medicines
        .map((m) => {
              'id': m.id,
              'name': m.name,
              'barcode': m.barcode,
              'category': m.category,
              'unit': m.unit,
              'purchasePrice': m.purchasePrice,
              'sellingPrice': m.sellingPrice,
              'mainStock': m.mainStock,
              'storeStock': m.storeStock,
              'lowStockThreshold': m.lowStockThreshold,
              'isScheduleH1': m.isScheduleH1,
              'createdAt': m.createdAt.toIso8601String(),
              'updatedAt': m.updatedAt.toIso8601String(),
              'batches': m.batches
                  .map((b) => {
                        'id': b.id,
                        'batchNo': b.batchNo,
                        'expiryDate': b.expiryDate.toIso8601String(),
                        'mainStock': b.mainStock,
                        'storeStock': b.storeStock,
                      })
                  .toList(),
            })
        .toList();
    return Response.ok(
      jsonEncode({
        'data': json,
        'count': json.length,
        'serverTime': DateTime.now().millisecondsSinceEpoch,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _medicinesSyncHandler(Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final list = (body['medicines'] as List?) ?? [];
    int upserted = 0;

    for (final item in list) {
      final name = item['name'] as String? ?? '';
      final barcode = item['barcode'] as String? ?? '';
      Condition<Medicine> cond = Medicine_.name.equals(name);
      if (barcode.isNotEmpty) {
        cond = cond.and(Medicine_.barcode.equals(barcode));
      }
      final existing = ObjectBoxService.instance.medicineBox.query(cond).build().findFirst();
      if (existing != null) {
        final serverUpdated = existing.updatedAt;
        final clientUpdated =
            DateTime.tryParse(item['updatedAt'] ?? '') ?? DateTime(2000);
        if (clientUpdated.isAfter(serverUpdated)) {
          existing
            ..name = item['name']
            ..barcode = item['barcode']
            ..sellingPrice = (item['sellingPrice'] as num).toDouble()
            ..mainStock = item['mainStock']
            ..storeStock = item['storeStock']
            ..isScheduleH1 = item['isScheduleH1'] ?? false;

          // Sync batches
          if (item['batches'] != null) {
            existing.batches.clear();
            for (var bItem in item['batches']) {
              existing.batches.add(MedicineBatch(
                id: 0,
                batchNo: bItem['batchNo'] ?? '',
                expiryDate: DateTime.tryParse(bItem['expiryDate'] ?? '') ?? DateTime.now(),
                mainStock: bItem['mainStock'] ?? 0,
                storeStock: bItem['storeStock'] ?? 0,
              ));
            }
          }

          ObjectBoxService.instance.medicineBox.put(existing);
          upserted++;
        }
      } else {
        final m = Medicine(
          name: item['name'],
          barcode: item['barcode'] ?? '',
          category: item['category'] ?? 'General',
          unit: item['unit'] ?? 'Pcs',
          purchasePrice: (item['purchasePrice'] as num).toDouble(),
          sellingPrice: (item['sellingPrice'] as num).toDouble(),
          mainStock: item['mainStock'] ?? 0,
          storeStock: item['storeStock'] ?? 0,
          isScheduleH1: item['isScheduleH1'] ?? false,
          updatedAt: DateTime.tryParse(item['updatedAt'] ?? ''),
        );
        if (item['batches'] != null) {
          for (var bItem in item['batches']) {
            m.batches.add(MedicineBatch(
              id: 0,
              batchNo: bItem['batchNo'] ?? '',
              expiryDate: DateTime.tryParse(bItem['expiryDate'] ?? '') ?? DateTime.now(),
              mainStock: bItem['mainStock'] ?? 0,
              storeStock: bItem['storeStock'] ?? 0,
            ));
          }
        }
        ObjectBoxService.instance.medicineBox.put(m);
        upserted++;
      }
    }

    broadcast({'event': 'medicines_updated'});
    return Response.ok(
      jsonEncode({'upserted': upserted}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _medicinesPushHandler(Request req) async {
    try {
      final item = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final box = ObjectBoxService.instance.medicineBox;
      final name = item['name'] as String? ?? '';
      final barcode = item['barcode'] as String? ?? '';
      
      // Match by Name + Barcode to prevent duplicates
      Condition<Medicine> cond = Medicine_.name.equals(name);
      if (barcode.isNotEmpty) {
        cond = cond.and(Medicine_.barcode.equals(barcode));
      }
      var existing = box.query(cond).build().findFirst();

      if (existing != null) {
        existing
          ..name = item['name']
          ..barcode = item['barcode'] ?? ''
          ..category = item['category'] ?? 'General'
          ..unit = item['unit'] ?? 'Pcs'
          ..purchasePrice = (item['purchasePrice'] as num).toDouble()
          ..sellingPrice = (item['sellingPrice'] as num).toDouble()
          ..mainStock = item['mainStock'] ?? 0
          ..storeStock = item['storeStock'] ?? 0
          ..lowStockThreshold = item['lowStockThreshold'] ?? 5
          ..isScheduleH1 = item['isScheduleH1'] ?? false
          ..updatedAt = DateTime.now();

        if (item['batches'] != null) {
          existing.batches.clear();
          for (var bItem in item['batches']) {
            existing.batches.add(MedicineBatch(
              id: 0,
              batchNo: bItem['batchNo'] ?? '',
              expiryDate: DateTime.tryParse(bItem['expiryDate'] ?? '') ?? DateTime.now(),
              mainStock: bItem['mainStock'] ?? 0,
              storeStock: bItem['storeStock'] ?? 0,
            ));
          }
        }
        box.put(existing);
      } else {
        final m = Medicine(
          name: item['name'],
          barcode: item['barcode'] ?? '',
          category: item['category'] ?? 'General',
          unit: item['unit'] ?? 'Pcs',
          purchasePrice: (item['purchasePrice'] as num).toDouble(),
          sellingPrice: (item['sellingPrice'] as num).toDouble(),
          mainStock: item['mainStock'] ?? 0,
          storeStock: item['storeStock'] ?? 0,
          lowStockThreshold: item['lowStockThreshold'] ?? 5,
          isScheduleH1: item['isScheduleH1'] ?? false,
        );
        if (item['batches'] != null) {
          for (var bItem in item['batches']) {
            m.batches.add(MedicineBatch(
              id: 0,
              batchNo: bItem['batchNo'] ?? '',
              expiryDate: DateTime.tryParse(bItem['expiryDate'] ?? '') ?? DateTime.now(),
              mainStock: bItem['mainStock'] ?? 0,
              storeStock: bItem['storeStock'] ?? 0,
            ));
          }
        }
        box.put(m);
      }

      broadcast({'event': 'sync_received'});
      _incomingDataController.add('medicines');
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub medicine push error: $e');
      return Response.internalServerError();
    }
  }

  Response _salesGetHandler(Request req) {
    final sinceStr = req.url.queryParameters['since'];
    final sinceMs = int.tryParse(sinceStr ?? '') ?? (DateTime.tryParse(sinceStr ?? '')?.millisecondsSinceEpoch) ?? 0;

    final box = ObjectBoxService.instance.saleBox;
    final query = box.query(Sale_.updatedAt.greaterThan(sinceMs - 1));
    final sales = query.build().find();
    
    debugPrint('Hub: Sales sync requested (since=$sinceMs). Returning ${sales.length} sales.');

    final json = sales
        .map((s) => {
              'id': s.id,
              'invoiceNo': s.invoiceNo,
              'patientId': s.patientId,
              'patientName': s.patientName,
              'patientPhone': s.patientPhone,
              'patientUhid': s.patientUhid,
              'subtotal': s.subtotal,
              'discount': s.discount,
              'taxRate': s.taxRate,
              'taxAmount': s.taxAmount,
              'total': s.total,
              'paymentMethod': s.paymentMethod,
              'cashAmount': s.cashAmount,
              'upiAmount': s.upiAmount,
              'cardAmount': s.cardAmount,
              'createdAt': s.createdAt.toIso8601String(),
              'updatedAt': s.updatedAt.toIso8601String(),
              'synced': s.synced,
              'isReturn': s.isReturn,
              'isClinicalDispense': s.isClinicalDispense,
              'linkedAppointmentId': s.linkedAppointmentId,
              'linkedProcedureId': s.linkedProcedureId,
              'itemsJson': s.itemsJson,
            })
        .toList();
    return Response.ok(
      jsonEncode({'data': json, 'serverTime': DateTime.now().millisecondsSinceEpoch}),
      headers: {'content-type': 'application/json'},
    );
  }

  void _revertHubInventory(Sale oldSale) {
    try {
      final list = jsonDecode(oldSale.itemsJson) as List;
      for (final jsonItem in list) {
        final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
        if (item.isProcedure) continue;
        final m = ObjectBoxService.instance.medicineBox
            .getAll()
            .where((x) => x.name == item.medicineName)
            .firstOrNull;
        if (m != null) {
          final qty = item.qty.toInt();
          if (qty > 0) {
            final batches = m.batches.toList();
            final batch = batches.where((b) => b.batchNo == item.batchNo).firstOrNull ?? (batches.isNotEmpty ? batches.first : null);
            if (batch != null) {
              if (oldSale.isClinicalDispense) {
                batch.mainStock += qty;
              } else {
                batch.storeStock += qty;
              }
              ObjectBoxService.instance.batchBox.put(batch);
            }
          } else if (qty < 0) {
            int toDeduct = qty.abs();
            final batches = m.batches.toList();
            final batch = batches.where((b) => b.batchNo == item.batchNo).firstOrNull ?? (batches.isNotEmpty ? batches.first : null);
            if (batch != null) {
              if (oldSale.isClinicalDispense) {
                batch.mainStock = (batch.mainStock - toDeduct).clamp(0, 999999);
              } else {
                batch.storeStock = (batch.storeStock - toDeduct).clamp(0, 999999);
              }
              ObjectBoxService.instance.batchBox.put(batch);
            }
          }

          if (oldSale.isClinicalDispense) {
            m.mainStock = (m.mainStock + qty).clamp(0, 999999);
          } else {
            m.storeStock = (m.storeStock + qty).clamp(0, 999999);
          }
          m.updatedAt = DateTime.now();
          ObjectBoxService.instance.medicineBox.put(m);
        }
      }
    } catch (e) {
      debugPrint('Hub inventory revert error: $e');
    }
  }

  void _deductHubInventory(Sale sale) {
    try {
      final list = jsonDecode(sale.itemsJson) as List;
      for (final jsonItem in list) {
        final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
        if (item.isProcedure) continue;
        final m = ObjectBoxService.instance.medicineBox
            .getAll()
            .where((x) => x.name == item.medicineName)
            .firstOrNull;

        if (m != null) {
          final int qty = item.qty.toInt();
          
          if (qty > 0) {
            int remaining = qty;
            final batches = m.batches.toList();
            batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
            for (var b in batches) {
              if (remaining <= 0) break;
              if (sale.isClinicalDispense) {
                if (b.mainStock > 0) {
                  final d = remaining > b.mainStock ? b.mainStock : remaining;
                  b.mainStock -= d;
                  remaining -= d;
                  ObjectBoxService.instance.batchBox.put(b);
                }
              } else {
                if (b.storeStock > 0) {
                  final d = remaining > b.storeStock ? b.storeStock : remaining;
                  b.storeStock -= d;
                  remaining -= d;
                  ObjectBoxService.instance.batchBox.put(b);
                }
              }
            }
          } else if (qty < 0) {
            int toRestore = qty.abs();
            final batches = m.batches.toList();
            if (batches.isNotEmpty) {
              batches.sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
              final latest = batches.first;
              if (sale.isClinicalDispense) {
                latest.mainStock += toRestore;
              } else {
                latest.storeStock += toRestore;
              }
              ObjectBoxService.instance.batchBox.put(latest);
            }
          }

          if (sale.isClinicalDispense) {
            m.mainStock = (m.mainStock - qty).clamp(0, 999999);
          } else {
            m.storeStock = (m.storeStock - qty).clamp(0, 999999);
          }
          m.updatedAt = DateTime.now();
          ObjectBoxService.instance.medicineBox.put(m);
        }
      }
    } catch (e) {
      debugPrint('Hub inventory deduct error: $e');
    }
  }

  Future<Response> _salesPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;

      // Resolve correct Hub patient ID (Robust resolution)
      int hubPatientId = 0;
      final pName = body['patientName'] as String? ?? '';
      final pPhone = body['patientPhone'] as String? ?? '';
      final pUhid = body['patientUhid'] as String? ?? '';

      // Try by UHID first (Stable key)
      if (pUhid.isNotEmpty) {
        final p = ObjectBoxService.instance.patientBox
            .query(Patient_.uhid.equals(pUhid))
            .build()
            .findFirst();
        if (p != null) hubPatientId = p.id;
      }

      // Fallback: Try by Name + Phone
      if (hubPatientId == 0 && pName.isNotEmpty) {
        final patients = ObjectBoxService.instance.patientBox.getAll();
        final match = patients.where((p) {
          final nMatch = p.name.trim().toLowerCase() == pName.trim().toLowerCase();
          final phMatch = pPhone.isNotEmpty && p.phone.trim() == pPhone.trim();
          return nMatch && (pPhone.isEmpty || phMatch);
        }).firstOrNull;
        if (match != null) hubPatientId = match.id;
      }

      final sale = Sale(
        invoiceNo: body['invoiceNo'] ?? '',
        patientId: hubPatientId > 0 ? hubPatientId : (body['patientId'] ?? 0),
        patientName: pName,
        patientPhone: pPhone,
        patientUhid: pUhid,
        subtotal: (body['subtotal'] as num?)?.toDouble() ?? 0.0,
        discount: (body['discount'] as num?)?.toDouble() ?? 0.0,
        taxRate: (body['taxRate'] as num?)?.toDouble() ?? 0.0,
        taxAmount: (body['taxAmount'] as num?)?.toDouble() ?? 0.0,
        total: (body['total'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: body['paymentMethod'] ?? 'cash',
        cashAmount: (body['cashAmount'] as num?)?.toDouble() ?? 0.0,
        upiAmount: (body['upiAmount'] as num?)?.toDouble() ?? 0.0,
        cardAmount: (body['cardAmount'] as num?)?.toDouble() ?? 0.0,
        createdAt: DateTime.tryParse(body['createdAt'] ?? '') ?? DateTime.now(),
        synced: true,
        isReturn: body['isReturn'] ?? false,
        isClinicalDispense: body['isClinicalDispense'] ?? false,
        itemsJson: body['itemsJson'] ?? '[]',
      );

      // Deduplication: check if invoiceNo already exists with the same millisecond timestamp
      final existing = ObjectBoxService.instance.saleBox
          .query(Sale_.invoiceNo.equals(sale.invoiceNo))
          .build()
          .find()
          .where((s) => s.createdAt.millisecondsSinceEpoch == sale.createdAt.millisecondsSinceEpoch)
          .firstOrNull;

      if (existing != null) {
        // Revert old inventory deductions on Hub
        _revertHubInventory(existing);

        // Update properties in-place
        existing
          ..patientId = sale.patientId
          ..patientName = sale.patientName
          ..patientPhone = sale.patientPhone
          ..patientUhid = sale.patientUhid
          ..subtotal = sale.subtotal
          ..discount = sale.discount
          ..taxRate = sale.taxRate
          ..taxAmount = sale.taxAmount
          ..total = sale.total
          ..paymentMethod = sale.paymentMethod
          ..cashAmount = sale.cashAmount
          ..upiAmount = sale.upiAmount
          ..cardAmount = sale.cardAmount
          ..createdAt = sale.createdAt
          ..updatedAt = DateTime.now()
          ..isReturn = sale.isReturn
          ..isClinicalDispense = sale.isClinicalDispense
          ..itemsJson = sale.itemsJson;

        ObjectBoxService.instance.saleBox.put(existing);

        // Apply new inventory deductions on Hub
        _deductHubInventory(existing);

        // Tell all clients that a new sync event occurred so they refresh
        broadcast({'event': 'sync_received'});
        broadcast({'event': 'medicines_updated'});
        _incomingDataController.add('sales');

        return Response.ok(
          jsonEncode({'status': 'success', 'saleId': existing.id, 'note': 'updated'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Save sale to Hub DB
      ObjectBoxService.instance.saleBox.put(sale);

      // Deduct inventory on Hub
      _deductHubInventory(sale);

      // Tell all clients that a new sync event occurred so they refresh
      broadcast({'event': 'sync_received'});
      // Specifically tell them medicines updated too
      broadcast({'event': 'medicines_updated'});
      // Tell Windows Hub UI to reload its providers
      _incomingDataController.add('sales');

      return Response.ok(
        jsonEncode({'status': 'success', 'saleId': sale.id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Error pushing sale - $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _patientsPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final p = Patient(
        uhid: body['uhid'] ?? '',
        name: body['name'] ?? '',
        phone: body['phone'] ?? '',
        gender: body['gender'] ?? 'Other',
        address: body['address'] ?? '',
        bloodGroup: body['bloodGroup'] ?? '',
        age: body['age'] ?? 0,
        createdAt: DateTime.tryParse(body['createdAt'] ?? '') ?? DateTime.now(),
      );

      // Conflict resolution: check if UHID already exists
      final existing = ObjectBoxService.instance.patientBox
          .query(Patient_.uhid.equals(p.uhid))
          .build()
          .findFirst();

      if (existing != null) {
        // Only merge if the name matches (or is very similar)
        // This prevents overwriting ABC with XYZ if they happen to get the same UHID (collision)
        final nameMatches = existing.name.trim().toLowerCase() == p.name.trim().toLowerCase();
        if (nameMatches) {
          p.id = existing.id;
        } else {
          // Collision detected: Same UHID but different name.
          // Append a suffix to the new UHID to make it unique on the Hub.
          p.uhid = "${p.uhid}-DUP";
          p.id = 0;
        }
      }

      ObjectBoxService.instance.patientBox.put(p);
      broadcast({'event': 'sync_received'});
      _incomingDataController.add('patients');

      return Response.ok(
        jsonEncode({'status': 'success', 'patientId': p.id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Patient Push Err: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _appointmentsPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      // 1. Resolve correct patient ID on Hub (Robust resolution)
      int hubPatientId = 0;
      final pName = body['patientName'] as String? ?? '';
      final pPhone = body['patientPhone'] as String? ?? '';
      final pUhid = body['patientUhid'] as String? ?? ''; // Future-proofing

      final patientBox = ObjectBoxService.instance.patientBox;
      
      // Try by UHID first (Stable key)
      if (pUhid.isNotEmpty) {
        final p = patientBox.query(Patient_.uhid.equals(pUhid)).build().findFirst();
        if (p != null) hubPatientId = p.id;
      }

      // Fallback: Try by Name + Phone
      if (hubPatientId == 0 && pName.isNotEmpty) {
        final patients = patientBox.getAll();
        final match = patients.where((p) {
          final nMatch = p.name.trim().toLowerCase() == pName.trim().toLowerCase();
          final phMatch = pPhone.isNotEmpty && p.phone.trim() == pPhone.trim();
          return nMatch && (pPhone.isEmpty || phMatch);
        }).firstOrNull;
        
        if (match != null) hubPatientId = match.id;
      }

      // 2. Resolve correct doctor ID on Hub by Name
      int hubDoctorId = 0;
      final dName = body['doctorName'] ?? '';
      if (dName.isNotEmpty) {
        final d = ObjectBoxService.instance.doctorBox
            .getAll()
            .where((d) => d.name == dName)
            .firstOrNull;
        if (d != null) hubDoctorId = d.id;
      }

      final scheduledAt =
          DateTime.tryParse(body['scheduledAt'] ?? '') ?? DateTime.now();
      final tokenNumber = body['tokenNumber'] ?? 0;

      final a = Appointment(
        patientId: hubPatientId > 0 ? hubPatientId : (body['patientId'] ?? 0),
        patientName: pName,
        patientPhone: pPhone,
        doctorId: hubDoctorId > 0 ? hubDoctorId : (body['doctorId'] ?? 0),
        doctorName: dName,
        tokenNumber: tokenNumber,
        status: body['status'] ?? kStatusWaiting,
        consultationFee: (body['consultationFee'] as num?)?.toDouble() ?? 0.0,
        notes: body['notes'] ?? '',
        scheduledAt: scheduledAt,
        createdAt: DateTime.tryParse(body['createdAt'] ?? '') ?? DateTime.now(),
        isWalkIn: body['isWalkIn'] ?? true,
        consultationBilled: body['consultationBilled'] ?? false,
      );

      // Match strictly by natural key to avoid ObjectBox ID sequence violations from Android
      final existing = ObjectBoxService.instance.appointmentBox
          .getAll()
          .where((x) =>
              x.patientName == pName &&
              x.tokenNumber == tokenNumber &&
              x.scheduledAt.year == scheduledAt.year &&
              x.scheduledAt.month == scheduledAt.month &&
              x.scheduledAt.day == scheduledAt.day)
          .firstOrNull;

      if (existing != null) {
        a.id = existing.id;
      } else {
        a.id = 0; // Force ObjectBox to generate a clean Hub ID
      }

      ObjectBoxService.instance.appointmentBox.put(a);
      broadcast({'event': 'sync_received'});
      _incomingDataController.add('appointments');

      return Response.ok(
        jsonEncode({'status': 'success', 'appointmentId': a.id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Appointment Push Err: $e');
      return Response.internalServerError();
    }
  }

  Response _patientsGetHandler(Request req) {
    final sinceStr = req.url.queryParameters['since'];
    final since = DateTime.tryParse(sinceStr ?? '') ?? DateTime(2000);

    final box = ObjectBoxService.instance.patientBox;
    final patients = box
        .query(Patient_.updatedAt.greaterThan(since.millisecondsSinceEpoch))
        .build()
        .find();

    final json = patients
        .map((p) => {
              'id': p.id,
              'uhid': p.uhid,
              'name': p.name,
              'phone': p.phone,
              'gender': p.gender,
              'address': p.address,
              'bloodGroup': p.bloodGroup,
              'age': p.age,
              'createdAt': p.createdAt.toIso8601String(),
              'updatedAt': p.updatedAt.toIso8601String(),
            })
        .toList();
    return Response.ok(
      jsonEncode({
        'data': json,
        'count': json.length,
        'serverTime': DateTime.now().millisecondsSinceEpoch,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _appointmentsGetHandler(Request req) {
    final appointments = ObjectBoxService.instance.appointmentBox.getAll();
    final patientBox = ObjectBoxService.instance.patientBox;
    final json = appointments.map((a) {
      final patient = patientBox.get(a.patientId);
      return {
        'id': a.id,
        'patientId': a.patientId,
        'patientUhid': patient?.uhid ?? '', // Added UHID for robust sync
        'patientName': a.patientName,
        'patientPhone': a.patientPhone,
        'doctorId': a.doctorId,
        'doctorName': a.doctorName,
        'tokenNumber': a.tokenNumber,
        'status': a.status,
        'consultationFee': a.consultationFee,
        'notes': a.notes,
        'scheduledAt': a.scheduledAt.toIso8601String(),
        'createdAt': a.createdAt.toIso8601String(),
        'isWalkIn': a.isWalkIn,
        'consultationBilled': a.consultationBilled,
      };
    }).toList();
    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _doctorsGetHandler(Request req) {
    final doctors = ObjectBoxService.instance.doctorBox.getAll();
    final json = doctors
        .map((d) => {
              'id': d.id,
              'name': d.name,
              'specialization': d.specialization,
              'consultationFee': d.consultationFee,
              'qualifications': d.qualifications,
              'phone': d.phone,
              'isActive': d.isActive,
              'createdAt': d.createdAt.toIso8601String(),
            })
        .toList();
    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _doctorsPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final d = Doctor(
        name: body['name'] ?? '',
        specialization: body['specialization'] ?? 'General',
        consultationFee: (body['consultationFee'] as num?)?.toDouble() ?? 0,
        qualifications: body['qualifications'] ?? '',
        phone: body['phone'] ?? '',
        isActive: body['isActive'] ?? true,
        createdAt: DateTime.tryParse(body['createdAt'] ?? '') ?? DateTime.now(),
      );

      // Prevent using purely Android-provided IDs. Match by name Instead.
      final existing = ObjectBoxService.instance.doctorBox
          .getAll()
          .where((x) => x.name == d.name)
          .firstOrNull;
      if (existing != null) {
        d.id = existing.id;
      } else {
        d.id = 0;
      }

      ObjectBoxService.instance.doctorBox.put(d);
      broadcast({'event': 'sync_received'});
      _incomingDataController.add('doctors');

      return Response.ok(
        jsonEncode({'status': 'success', 'doctorId': d.id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Doctor Push Err: $e');
      return Response.internalServerError();
    }
  }

  Response _prescriptionsGetHandler(Request req) {
    final sinceStr = req.url.queryParameters['since'];
    final since = DateTime.tryParse(sinceStr ?? '') ?? DateTime(2000);
    final prescriptions = ObjectBoxService.instance.prescriptionBox.getAll();
    final patientBox = ObjectBoxService.instance.patientBox;
    final json = prescriptions.map((p) {
      final patient = patientBox.get(p.patientId);
      return {
        'id': p.id,
        'appointmentId': p.appointmentId,
        'patientId': p.patientId,
        'patientUhid': patient?.uhid ?? '',
        'patientName': p.patientName,
        'doctorId': p.doctorId,
        'doctorName': p.doctorName,
        'diagnosis': p.diagnosis,
        'complaints': p.complaints,
        'notes': p.notes,
        'itemsJson': p.itemsJson,
        'labTestsJson': p.labTestsJson,
        'vitalsJson': p.vitalsJson,
        'imagesJson': p.imagesJson,
        'proceduresJson': p.proceduresJson,
        'dispensed': p.dispensed,
        'createdAt': p.createdAt.toIso8601String(),
        'updatedAt': p.updatedAt.toIso8601String(),
      };
    }).toList();
    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _prescriptionsPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      
      // 1. Resolve local IDs using natural keys (UHID and Token+Date)
      final uhid = body['patientUhid'] as String? ?? '';
      final token = body['tokenNumber'] as int? ?? 0;
      final createdAt = DateTime.tryParse(body['createdAt'] ?? '') ?? DateTime.now();
      
      int resolvedPatientId = 0;
      if (uhid.isNotEmpty) {
        final p = ObjectBoxService.instance.patientBox
            .query(Patient_.uhid.equals(uhid))
            .build()
            .findFirst();
        if (p != null) resolvedPatientId = p.id;
      }

      int resolvedApptId = 0;
      if (token > 0) {
        final appt = ObjectBoxService.instance.appointmentBox
            .getAll()
            .where((a) =>
                a.tokenNumber == token &&
                a.scheduledAt.year == createdAt.year &&
                a.scheduledAt.month == createdAt.month &&
                a.scheduledAt.day == createdAt.day)
            .firstOrNull;
        if (appt != null) resolvedApptId = appt.id;
      }

      // 2. Create/Update Prescription object
      final p = Prescription(
        appointmentId: resolvedApptId > 0 ? resolvedApptId : (body['appointmentId'] ?? 0),
        patientId: resolvedPatientId > 0 ? resolvedPatientId : (body['patientId'] ?? 0),
        patientName: body['patientName'] ?? '',
        doctorId: body['doctorId'] ?? 0,
        doctorName: body['doctorName'] ?? '',
        diagnosis: body['diagnosis'] ?? '',
        complaints: body['complaints'] ?? '',
        notes: body['notes'] ?? '',
        itemsJson: body['itemsJson'] ?? '[]',
        labTestsJson: body['labTestsJson'] ?? '[]',
        vitalsJson: body['vitalsJson'] ?? '{}',
        imagesJson: body['imagesJson'] ?? '[]',
        proceduresJson: body['proceduresJson'] ?? '[]',
        dispensed: body['dispensed'] ?? false,
        createdAt: createdAt,
      );

      // Check for existing prescription by natural key (Patient + Date)
      final existing = ObjectBoxService.instance.prescriptionBox
          .getAll()
          .where((x) =>
              x.patientId == p.patientId &&
              x.createdAt.year == p.createdAt.year &&
              x.createdAt.month == p.createdAt.month &&
              x.createdAt.day == p.createdAt.day)
          .firstOrNull;

      if (existing != null) {
        p.id = existing.id;
      }
      
      ObjectBoxService.instance.prescriptionBox.put(p);
      
      // 3. Update appointment status to 'pharmacy' on Hub if needed
      if (resolvedApptId > 0) {
        final appt = ObjectBoxService.instance.appointmentBox.get(resolvedApptId);
        if (appt != null && (appt.status == kStatusWithDoctor || appt.status == kStatusWaiting)) {
          appt.status = kStatusPharmacy;
          ObjectBoxService.instance.appointmentBox.put(appt);
          debugPrint('Hub: Updated appointment $resolvedApptId to pharmacy status');
        }
      }

      debugPrint('Hub: Processed prescription for ${p.patientName} (Resolved IDs: Patient=$resolvedPatientId, Appt=$resolvedApptId)');
      
      broadcast({'event': 'sync_received'});
      _incomingDataController.add('prescriptions');

      return Response.ok(
        jsonEncode({'status': 'success', 'prescriptionId': p.id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Prescription Push Err: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _doctorsDeleteHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final id = body['id'] as int?;
      if (id != null && id > 0) {
        ObjectBoxService.instance.doctorBox.remove(id);
        broadcast({'event': 'sync_received'});
        _incomingDataController.add('doctors');
      }
      return Response.ok(
        jsonEncode({'status': 'success'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Doctor Delete Err: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _patientsDeleteHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final id = body['id'] as int?;
      final uhid = body['uhid'] as String? ?? '';
      
      final box = ObjectBoxService.instance.patientBox;
      Patient? p;
      if (id != null && id > 0) {
        p = box.get(id);
      } else if (uhid.isNotEmpty) {
        p = box.query(Patient_.uhid.equals(uhid)).build().findFirst();
      }

      if (p != null) {
        final actualUhid = p.uhid;
        box.remove(p.id);
        // Broadcast specific deletion so Android can remove it from local Box
        broadcast({'event': 'patient_deleted', 'uhid': actualUhid});
        _incomingDataController.add('patients');
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub patient delete error: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _medicinesDeleteHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final id = body['id'] as int?;
      final barcode = body['barcode'] as String? ?? '';
      final name = body['name'] as String? ?? '';

      final box = ObjectBoxService.instance.medicineBox;
      Medicine? m;
      if (id != null && id > 0) {
        m = box.get(id);
      } else if (barcode.isNotEmpty) {
        m = box.query(Medicine_.barcode.equals(barcode)).build().findFirst();
      } else if (name.isNotEmpty) {
        m = box.query(Medicine_.name.equals(name)).build().findFirst();
      }

      if (m != null) {
        final actualBarcode = m.barcode;
        final actualName = m.name;
        box.remove(m.id);
        broadcast({
          'event': 'medicine_deleted',
          'barcode': actualBarcode,
          'name': actualName
        });
        _incomingDataController.add('inventory');
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub medicine delete error: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _prescriptionsDeleteHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final id = body['id'] as int?;
      if (id != null && id > 0) {
        ObjectBoxService.instance.prescriptionBox.remove(id);
        broadcast({'event': 'sync_received'});
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub prescription delete error: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _transfersGetHandler(Request req) async {
    final transfers = ObjectBoxService.instance.transferBox.getAll();
    final json = transfers
        .map((t) => {
              'id': t.id,
              'medicineId': t.medicineId,
              'medicineName': t.medicineName,
              'qty': t.qty,
              'fromWarehouse': t.fromWarehouse,
              'toWarehouse': t.toWarehouse,
              'transferredAt': t.transferredAt.toIso8601String(),
              'note': t.note,
              'transferredBy': t.transferredBy,
            })
        .toList();
    return Response.ok(
      jsonEncode({
        'data': json,
        'serverTime': DateTime.now().millisecondsSinceEpoch,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _transfersPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final transfer = StockTransfer(
        medicineId: body['medicineId'],
        medicineName: body['medicineName'],
        qty: body['qty'],
        fromWarehouse: body['fromWarehouse'],
        toWarehouse: body['toWarehouse'],
        note: body['note'] ?? '',
        transferredBy: body['transferredBy'] ?? '',
        transferredAt:
            DateTime.tryParse(body['transferredAt'] ?? '') ?? DateTime.now(),
      );

      // Save transfer to Hub
      ObjectBoxService.instance.transferBox.put(transfer);

      // Update medicine stock on Hub
      final m = ObjectBoxService.instance.medicineBox.get(transfer.medicineId);
      if (m != null) {
        if (transfer.fromWarehouse == 'main' &&
            transfer.toWarehouse == 'store') {
          m.mainStock = (m.mainStock - transfer.qty).clamp(0, 999999);
          m.storeStock += transfer.qty;
        } else if (transfer.fromWarehouse == 'store' &&
            transfer.toWarehouse == 'main') {
          m.storeStock = (m.storeStock - transfer.qty).clamp(0, 999999);
          m.mainStock += transfer.qty;
        }
        m.updatedAt = DateTime.now();
        ObjectBoxService.instance.medicineBox.put(m);
      }

      broadcast({'event': 'sync_received'});
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub transfer push error: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _syncHandler(Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    // Generic sync: forward to broadcast
    broadcast({'event': 'sync_received', 'payload': body});
    return Response.ok(
      jsonEncode({'status': 'received'}),
      headers: {'content-type': 'application/json'},
    );
  }

  // ─── Prescription Templates ───────────────────────────────────────────────

  Response _templatesGetHandler(Request req) {
    final templates = ObjectBoxService.instance.templateBox.getAll();
    final json = templates
        .map((t) => {
              'id': t.id,
              'name': t.name,
              'diagnosis': t.diagnosis,
              'complaints': t.complaints,
              'notes': t.notes,
              'itemsJson': t.itemsJson,
              'labTestsJson': t.labTestsJson,
              'doctorId': t.doctorId,
              'createdAt': t.createdAt.toIso8601String(),
            })
        .toList();
    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _templatesPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = body['name'] as String? ?? '';
      if (name.isEmpty) return Response.badRequest();

      // Upsert by name
      final existing = ObjectBoxService.instance.templateBox
          .getAll()
          .where((t) => t.name == name)
          .firstOrNull;

      final t = existing ?? PrescriptionTemplate(name: name);
      t.name = name;
      t.diagnosis = body['diagnosis'] ?? '';
      t.complaints = body['complaints'] ?? '';
      t.notes = body['notes'] ?? '';
      t.itemsJson = body['itemsJson'] ?? '[]';
      t.labTestsJson = body['labTestsJson'] ?? '[]';
      t.doctorId = body['doctorId'] ?? 0;

      ObjectBoxService.instance.templateBox.put(t);
      broadcast({'event': 'sync_received'});
      _incomingDataController.add('templates');

      return Response.ok(
        jsonEncode({'status': 'success', 'templateId': t.id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Template Push Err: $e');
      return Response.internalServerError();
    }
  }

  // ─── Patient Photos ───────────────────────────────────────────────────────

  Future<Response> _patientPhotosGetHandler(Request req) async {
    try {
      // Optional ?uhid= filter for lazy per-patient loading
      final filterUhid = req.url.queryParameters['uhid'];

      final photos = ObjectBoxService.instance.patientImageBox.getAll();
      final patientBox = ObjectBoxService.instance.patientBox;
      final List<Map<String, dynamic>> result = [];

      for (final photo in photos) {
        // Resolve the patient by ID to get their UHID
        final patient = patientBox.get(photo.patientId);
        final uhid = patient?.uhid ?? '';

        // If caller requested a specific patient, skip others
        if (filterUhid != null && filterUhid.isNotEmpty && uhid != filterUhid) {
          continue;
        }

        final file = File(photo.imagePath);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final base64Data = base64Encode(bytes);
        final filename = photo.imagePath.replaceAll('\\', '/').split('/').last;
        result.add({
          'patientUhid': uhid, // ← UHID so Android can resolve local ID
          'category': photo.category,
          'date': photo.date.toIso8601String(),
          'createdAt': photo.createdAt.toIso8601String(),
          'filename': filename,
          'imageData': base64Data,
        });
      }
      return Response.ok(
        jsonEncode({'data': result, 'count': result.length}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Patient Photos GET Err: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _patientPhotosPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final patientUhid = body['patientUhid'] as String? ?? '';
      final category = body['category'] as String? ?? 'General';
      final date = DateTime.tryParse(body['date'] ?? '') ?? DateTime.now();
      final filename = body['filename'] as String? ??
          '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imageData = body['imageData'] as String? ?? '';

      if (patientUhid.isEmpty || imageData.isEmpty)
        return Response.badRequest();

      // Resolve UHID → Hub's local patientId
      final patient = ObjectBoxService.instance.patientBox
          .getAll()
          .where((p) => p.uhid == patientUhid)
          .firstOrNull;
      if (patient == null) {
        debugPrint(
            'Hub: PatientPhoto Push — patient UHID $patientUhid not found');
        return Response.badRequest(
          body: jsonEncode({'error': 'Patient not found: $patientUhid'}),
          headers: {'content-type': 'application/json'},
        );
      }
      final patientId = patient.id;

      // Save the image file to Hub's patient_photos directory
      final appDocDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${appDocDir.path}/patient_photos/$patientId');
      if (!await photoDir.exists()) await photoDir.create(recursive: true);

      final savedPath = '${photoDir.path}/$filename';
      final bytes = base64Decode(imageData);
      await File(savedPath).writeAsBytes(bytes);

      // Check if already exists in ObjectBox
      final existing = ObjectBoxService.instance.patientImageBox
          .getAll()
          .where(
              (p) => p.imagePath.endsWith(filename) && p.patientId == patientId)
          .firstOrNull;

      if (existing == null) {
        final pImage = PatientImage(
          patientId: patientId,
          imagePath: savedPath,
          category: category,
          date: date,
        );
        ObjectBoxService.instance.patientImageBox.put(pImage);
      }

      broadcast({'event': 'photo_received', 'path': savedPath});
      _incomingDataController.add('patient_photos:$savedPath');

      return Response.ok(
        jsonEncode({'status': 'success'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Patient Photos Push Err: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _prescriptionPhotosPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final filename = body['filename'] as String? ??
          'presc_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imageData = body['imageData'] as String? ?? '';

      if (imageData.isEmpty) return Response.badRequest();

      final appDocDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${appDocDir.path}/prescription_photos');
      if (!await photoDir.exists()) await photoDir.create(recursive: true);

      final savedPath = '${photoDir.path}/$filename';
      final bytes = base64Decode(imageData);
      await File(savedPath).writeAsBytes(bytes);

      return Response.ok(
        jsonEncode({'status': 'success', 'path': savedPath}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Prescription Photos Push Err: $e');
      return Response.internalServerError();
    }
  }

  // ---- Middleware ----

  Middleware _corsMiddleware() => (Handler inner) => (Request req) async {
        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders());
        }
        final resp = await inner(req);
        return resp.change(headers: _corsHeaders());
      };

  void _migrateSyncMetadata() {
    final boxP = ObjectBoxService.instance.patientBox;
    final boxS = ObjectBoxService.instance.saleBox;
    final boxPr = ObjectBoxService.instance.prescriptionBox;
    
    int migrated = 0;
    
    // Since ObjectBox initialization might have some records with updatedAt as epoch or 0
    final epoch = DateTime(2000);

    for (var p in boxP.getAll()) {
      // In ObjectBox, uninitialized Date/int might look like 0 or very early dates
      if (p.updatedAt.isBefore(epoch)) {
        p.updatedAt = p.createdAt;
        boxP.put(p);
        migrated++;
      }
    }
    
    for (var s in boxS.getAll()) {
      if (s.updatedAt.isBefore(epoch)) {
        s.updatedAt = s.createdAt;
        boxS.put(s);
        migrated++;
      }
    }
    
    for (var pr in boxPr.getAll()) {
      if (pr.updatedAt.isBefore(epoch)) {
        pr.updatedAt = pr.createdAt;
        boxPr.put(pr);
        migrated++;
      }
    }
    
    if (migrated > 0) {
      debugPrint('Hub: Migrated $migrated legacy records with missing sync metadata.');
    }
  }

  Future<Response> _salesDeleteHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final invoiceNo = body['invoiceNo'] as String? ?? '';
      if (invoiceNo.isEmpty) return Response.badRequest();

      final box = ObjectBoxService.instance.saleBox;
      final sale =
          box.query(Sale_.invoiceNo.equals(invoiceNo)).build().findFirst();

      if (sale != null) {
        // Reverse inventory on Hub
        final items = jsonDecode(sale.itemsJson) as List;
        for (final jsonItem in items) {
          final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
          final m = ObjectBoxService.instance.medicineBox
              .getAll()
              .where((x) => x.name == item.medicineName)
              .firstOrNull;
          if (m != null) {
            final qtyToRestore = item.qty.toInt();
            // Reversing: if it was a sale (positive qty), we add it back.
            // If it was a return (negative qty), we deduct it.
            // Also adjust batch
            final batches = m.batches.toList();
            if (batches.isNotEmpty) {
              batches.sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
              final latest = batches.first;
              if (sale.isClinicalDispense) {
                latest.mainStock = (latest.mainStock + qtyToRestore).clamp(0, 999999);
              } else {
                latest.storeStock = (latest.storeStock + qtyToRestore).clamp(0, 999999);
              }
              ObjectBoxService.instance.batchBox.put(latest);
            }

            if (sale.isClinicalDispense) {
              m.mainStock = (m.mainStock + qtyToRestore).clamp(0, 999999);
            } else {
              m.storeStock = (m.storeStock + qtyToRestore).clamp(0, 999999);
            }
            m.updatedAt = DateTime.now();
            ObjectBoxService.instance.medicineBox.put(m);
          }
        }
        box.remove(sale.id);
        broadcast({'event': 'sync_received'});
        broadcast({'event': 'medicines_updated'});
        broadcast({'event': 'sale_deleted', 'invoiceNo': invoiceNo});
        _incomingDataController.add('sales');
      }

      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub: Sale Delete Err: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _templatesDeleteHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = body['name'] as String? ?? '';
      if (name.isEmpty) return Response.badRequest();

      final box = ObjectBoxService.instance.templateBox;
      final t = box.query(PrescriptionTemplate_.name.equals(name)).build().findFirst();
      if (t != null) {
        box.remove(t.id);
        broadcast({'event': 'sync_received'});
        _incomingDataController.add('templates');
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub: Template Delete Err: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _patientPhotosDeleteHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final uhid = body['uhid'] as String? ?? '';
      final filename = body['fileName'] as String? ?? '';
      if (uhid.isEmpty || filename.isEmpty) return Response.badRequest();

      // Resolve patient to get ID
      final patient = ObjectBoxService.instance.patientBox
          .query(Patient_.uhid.equals(uhid))
          .build()
          .findFirst();
      if (patient == null) return Response.notFound(jsonEncode({'error': 'Patient not found'}));

      final box = ObjectBoxService.instance.patientImageBox;
      final photos = box.query(PatientImage_.patientId.equals(patient.id)).build().find();
      
      for (final photo in photos) {
        if (photo.imagePath.replaceAll('\\', '/').endsWith(filename)) {
          // Delete file
          final file = File(photo.imagePath);
          if (await file.exists()) {
            await file.delete();
          }
          box.remove(photo.id);
        }
      }

      broadcast({'event': 'sync_received'});
      _incomingDataController.add('patients');

      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      debugPrint('Hub: Photo Delete Err: $e');
      return Response.internalServerError();
    }
  }

  Map<String, String> _corsHeaders() => {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      };

  Handler _withAuth(Handler handler) => (Request req) {
        final auth = req.headers['authorization'] ?? '';
        if (!auth.startsWith('Bearer ')) {
          return Response.forbidden(
            jsonEncode({'error': 'Missing token'}),
            headers: {'content-type': 'application/json'},
          );
        }
        try {
          JWT.verify(auth.substring(7), SecretKey(_jwtSecret));
        } catch (_) {
          return Response.forbidden(
            jsonEncode({'error': 'Invalid token'}),
            headers: {'content-type': 'application/json'},
          );
        }
        return handler(req);
      };

  Middleware _gzipMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final response = await innerHandler(request);
        if (request.headers['accept-encoding']?.contains('gzip') ?? false) {
          // If body is empty or already compressed, skip
          if (response.contentLength == 0 ||
              response.headers['content-encoding'] == 'gzip') {
            return response;
          }
          final bodyBytes = await response.read().fold<List<int>>([], (p, e) => p..addAll(e));
          final compressed = gzip.encode(bodyBytes);
          return response.change(
            body: compressed,
            headers: {
              ...response.headers,
              'content-encoding': 'gzip',
              'content-length': compressed.length.toString(),
            },
          );
        }
        return response;
      };
    };
  }

  /// Processes data changes pushed from companion apps via Firebase Fallback (Tier 3).
  /// This ensures that even if the Hub is not directly reachable, it eventually catches up.
  Future<void> handleExternalDelta(Map<String, dynamic> delta) async {
    final entity = delta['entity'];
    final action = delta['action'];
    final data = delta['data'] as Map<String, dynamic>;
    final docId = delta['id'] as String?;

    debugPrint('Hub [Firebase Delta]: Processing $entity ($action)');

    try {
      if (entity == 'sale' && action == 'create') {
        final sale = Sale(
          invoiceNo: data['invoiceNo'] ?? '',
          patientId: data['patientId'] ?? 0,
          patientName: data['patientName'] ?? '',
          patientPhone: data['patientPhone'] ?? '',
          subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
          discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
          taxRate: (data['taxRate'] as num?)?.toDouble() ?? 0.0,
          taxAmount: (data['taxAmount'] as num?)?.toDouble() ?? 0.0,
          total: (data['total'] as num?)?.toDouble() ?? 0.0,
          paymentMethod: data['paymentMethod'] ?? 'cash',
          cashAmount: (data['cashAmount'] as num?)?.toDouble() ?? 0.0,
          upiAmount: (data['upiAmount'] as num?)?.toDouble() ?? 0.0,
          cardAmount: (data['cardAmount'] as num?)?.toDouble() ?? 0.0,
          createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
          synced: true,
          isReturn: data['isReturn'] ?? false,
          isClinicalDispense: data['isClinicalDispense'] ?? false,
          itemsJson: data['itemsJson'] ?? '[]',
        );

        // Check for duplicates
        final existing = ObjectBoxService.instance.saleBox.query(Sale_.invoiceNo.equals(sale.invoiceNo)).build().findFirst();
        if (existing == null) {
          ObjectBoxService.instance.saleBox.put(sale);
          
          // Deduct Inventory
          _deductHubInventory(sale);
          
          broadcast({'event': 'sync_received'});
          broadcast({'event': 'sales_updated'});
          _incomingDataController.add('sales');

          // Mirror back to Cloud so all devices (including the one that sent it) see it confirmed
          await FirebaseSyncService.instance.broadcastUpdate('sales', sale.toJson());
          // Also broadcast updated medicines (stock deducted)
          final list = jsonDecode(sale.itemsJson) as List;
          for (final jsonItem in list) {
            final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
            final m = ObjectBoxService.instance.medicineBox.getAll().where((x) => x.name == item.medicineName).firstOrNull;
            if (m != null) {
              await FirebaseSyncService.instance.broadcastUpdate('medicines', m.toJson());
            }
          }
        } else {
          // Revert old inventory deductions on Hub
          _revertHubInventory(existing);

          // Update properties in-place
          existing
            ..patientId = sale.patientId
            ..patientName = sale.patientName
            ..patientPhone = sale.patientPhone
            ..patientUhid = sale.patientUhid
            ..subtotal = sale.subtotal
            ..discount = sale.discount
            ..taxRate = sale.taxRate
            ..taxAmount = sale.taxAmount
            ..total = sale.total
            ..paymentMethod = sale.paymentMethod
            ..cashAmount = sale.cashAmount
            ..upiAmount = sale.upiAmount
            ..cardAmount = sale.cardAmount
            ..createdAt = sale.createdAt
            ..updatedAt = DateTime.now()
            ..isReturn = sale.isReturn
            ..isClinicalDispense = sale.isClinicalDispense
            ..itemsJson = sale.itemsJson;

          ObjectBoxService.instance.saleBox.put(existing);

          // Apply new inventory deductions on Hub
          _deductHubInventory(existing);

          broadcast({'event': 'sync_received'});
          broadcast({'event': 'sales_updated'});
          _incomingDataController.add('sales');

          // Mirror back to Cloud so all devices see it confirmed
          await FirebaseSyncService.instance.broadcastUpdate('sales', existing.toJson());
          // Also broadcast updated medicines (stock deducted)
          final list = jsonDecode(existing.itemsJson) as List;
          for (final jsonItem in list) {
            final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
            final m = ObjectBoxService.instance.medicineBox.getAll().where((x) => x.name == item.medicineName).firstOrNull;
            if (m != null) {
              await FirebaseSyncService.instance.broadcastUpdate('medicines', m.toJson());
            }
          }
        }
      } else if (entity == 'patient' && action == 'create') {
        final p = Patient(
          uhid: data['uhid'] ?? '',
          name: data['name'] ?? '',
          phone: data['phone'] ?? '',
          gender: data['gender'] ?? 'Other',
          address: data['address'] ?? '',
          bloodGroup: data['bloodGroup'] ?? '',
          age: data['age'] ?? 0,
          createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
        );
        final existing = ObjectBoxService.instance.patientBox.query(Patient_.uhid.equals(p.uhid)).build().findFirst();
        if (existing != null) p.id = existing.id;
        ObjectBoxService.instance.patientBox.put(p);
        broadcast({'event': 'patients_updated'});
        _incomingDataController.add('patients');
        
        // Mirror to cloud
        await FirebaseSyncService.instance.broadcastUpdate('patients', p.toJson());
      } else if (entity == 'medicine') {
        final m = Medicine.fromJson(data);
        m.id = 0; // Force ID 0 for Hub (ObjectBox IDs are local)
        for (var b in m.batches) {
          b.id = 0; // Force Batch IDs to 0 as well
        }

        // Deduplicate by name or barcode
        Condition<Medicine> cond = Medicine_.name.equals(m.name);
        if (m.barcode.isNotEmpty) {
          cond = cond.and(Medicine_.barcode.equals(m.barcode));
        }
        final existing = ObjectBoxService.instance.medicineBox.query(cond).build().findFirst();
        
        if (existing != null) {
          m.id = existing.id;
        }
        ObjectBoxService.instance.medicineBox.put(m);
        broadcast({'event': 'medicines_updated'});
        broadcast({'event': 'sync_received'});
        _incomingDataController.add('inventory');
      } else if (entity == 'appointment' && action == 'create') {
        final appt = Appointment.fromJson(data);
        appt.id = 0; // Force ID 0
        
        // Deduplicate by patient name and date
        final existing = ObjectBoxService.instance.appointmentBox.query(
          Appointment_.patientName.equals(appt.patientName).and(
          Appointment_.scheduledAt.equals(appt.scheduledAt.millisecondsSinceEpoch))
        ).build().findFirst();
        
        if (existing != null) appt.id = existing.id;
        ObjectBoxService.instance.appointmentBox.put(appt);
        
        broadcast({'event': 'appointments_updated'});
        broadcast({'event': 'sync_received'});
        _incomingDataController.add('appointments');
        
        // Mirror to cloud
        await FirebaseSyncService.instance.broadcastUpdate('appointments', appt.toJson());
      } else if (entity == 'prescription' && action == 'create') {
        final sc = Prescription.fromJson(data);
        sc.id = 0; // Reset ID for Hub
        final existing = ObjectBoxService.instance.prescriptionBox
            .query(Prescription_.patientName.equals(sc.patientName))
            .build()
            .find()
            .where((x) => x.createdAt.millisecondsSinceEpoch == sc.createdAt.millisecondsSinceEpoch)
            .firstOrNull;
        if (existing != null) sc.id = existing.id;
        ObjectBoxService.instance.prescriptionBox.put(sc);
        broadcast({'event': 'sync_received'});
        _incomingDataController.add('prescriptions');
        
        // Mirror to cloud
        await FirebaseSyncService.instance.broadcastUpdate('prescriptions', sc.toJson());
      } else if (action == 'delete') {
        if (entity == 'patient') {
          final uhid = data['uhid'] as String? ?? '';
          final p = ObjectBoxService.instance.patientBox.query(Patient_.uhid.equals(uhid)).build().findFirst();
          if (p != null) {
            ObjectBoxService.instance.patientBox.remove(p.id);
            broadcast({'event': 'patient_deleted', 'uhid': uhid});
            _incomingDataController.add('patients');
          }
        } else if (entity == 'medicine') {
          final barcode = data['barcode'] as String? ?? '';
          final name = data['name'] as String? ?? '';
          Condition<Medicine>? cond;
          if (barcode.isNotEmpty) cond = Medicine_.barcode.equals(barcode);
          if (name.isNotEmpty) {
            final nameCond = Medicine_.name.equals(name);
            cond = cond == null ? nameCond : cond.and(nameCond);
          }
          if (cond != null) {
            final m = ObjectBoxService.instance.medicineBox.query(cond).build().findFirst();
            if (m != null) {
              ObjectBoxService.instance.medicineBox.remove(m.id);
              broadcast({'event': 'medicine_deleted', 'barcode': m.barcode, 'name': m.name});
              _incomingDataController.add('inventory');
            }
          }
        } else if (entity == 'sale') {
          final invNo = data['invoiceNo'] as String? ?? '';
          final s = ObjectBoxService.instance.saleBox.query(Sale_.invoiceNo.equals(invNo)).build().findFirst();
          if (s != null) {
            ObjectBoxService.instance.saleBox.remove(s.id);
            broadcast({'event': 'sale_deleted', 'invoiceNo': invNo});
            _incomingDataController.add('sales');
          }
        } else if (entity == 'procedure') {
          final name = data['name'] as String? ?? '';
          final p = ObjectBoxService.instance.procedureBox
              .query(Procedure_.name.equals(name))
              .build()
              .findFirst();
          if (p != null) {
            ObjectBoxService.instance.procedureBox.remove(p.id);
            broadcast({'event': 'procedures_updated'});
            _incomingDataController.add('procedures');
          }
        }
      } else if (entity == 'procedure') {
        final p = Procedure.fromJson(data);
        p.id = 0;
        final existing = ObjectBoxService.instance.procedureBox
            .query(Procedure_.name.equals(p.name))
            .build()
            .findFirst();
        if (existing != null) p.id = existing.id;
        ObjectBoxService.instance.procedureBox.put(p);
        broadcast({'event': 'procedures_updated'});
        _incomingDataController.add('procedures');
        await FirebaseSyncService.instance.broadcastUpdate('procedures', p.toJson());
      }

      // Mark as processed in Firebase
      if (docId != null) {
        await FirebaseSyncService.instance.markAsProcessed(docId);
      }
    } catch (e) {
      debugPrint('Hub: Error processing Firebase delta: $e');
    }
  }

  /// Hub-side: Broadcasts all critical data to Firebase for companion apps' offline consumption.
  /// Now performs "Mirroring" - deletes items from Cloud that no longer exist locally.
  Future<void> broadcastAllToCloud() async {
    debugPrint('Hub: Starting full Cloud Mirror Sync...');
    int pushCount = 0;
    int pruneCount = 0;
    
    try {
      // --- 1. Mirror Users ---
      final users = ObjectBoxService.instance.userBox.getAll();
      final localUserNames = users.map((u) => u.name).toSet();
      final cloudUsers = await FirebaseSyncService.instance.fetchCollection('users');
      for (var cu in cloudUsers) {
        final name = cu['name']?.toString();
        if (name != null && !localUserNames.contains(name)) {
          await FirebaseSyncService.instance.deleteDocument('users', name);
          pruneCount++;
        }
      }
      for (var u in users) {
        await FirebaseSyncService.instance.broadcastUpdate('users', u.toJson());
        pushCount++;
      }

      // --- 2. Mirror Medicines ---
      final meds = ObjectBoxService.instance.medicineBox.getAll();
      // Barcode is our docId for medicines
      final localBarcodes = meds.map((m) => m.barcode.isEmpty ? m.id.toString() : m.barcode).toSet();
      final cloudMeds = await FirebaseSyncService.instance.fetchCollection('medicines');
      for (var cm in cloudMeds) {
        final cloudId = cm['cloudId']?.toString();
        if (cloudId != null && !localBarcodes.contains(cloudId)) {
          await FirebaseSyncService.instance.deleteDocument('medicines', cloudId);
          pruneCount++;
        }
      }
      for (var m in meds) {
        await FirebaseSyncService.instance.broadcastUpdate('medicines', m.toJson());
        pushCount++;
      }

      // --- 3. Mirror Patients ---
      final patients = ObjectBoxService.instance.patientBox.getAll();
      final localUhids = patients.map((p) => p.uhid.isEmpty ? p.id.toString() : p.uhid).toSet();
      final cloudPatients = await FirebaseSyncService.instance.fetchCollection('patients');
      for (var cp in cloudPatients) {
        final cloudId = cp['cloudId']?.toString();
        if (cloudId != null && !localUhids.contains(cloudId)) {
          await FirebaseSyncService.instance.deleteDocument('patients', cloudId);
          pruneCount++;
        }
      }
      for (var p in patients) {
        await FirebaseSyncService.instance.broadcastUpdate('patients', p.toJson());
        pushCount++;
      }

      // --- 4. Mirror Sales (Limited to recent) ---
      final sales = ObjectBoxService.instance.saleBox.query().order(Sale_.id, flags: Order.descending).build().find();
      final limitedSales = sales.length > 50 ? sales.sublist(0, 50) : sales;
      final localInvoices = limitedSales.map((s) => s.invoiceNo).toSet();
      final cloudSales = await FirebaseSyncService.instance.fetchCollection('sales');
      for (var cs in cloudSales) {
        final cloudId = cs['cloudId']?.toString();
        if (cloudId != null && !localInvoices.contains(cloudId)) {
          await FirebaseSyncService.instance.deleteDocument('sales', cloudId);
          pruneCount++;
        }
      }
      for (var s in limitedSales) {
        await FirebaseSyncService.instance.broadcastUpdate('sales', s.toJson());
        pushCount++;
      }

      // --- 5. Mirror Procedures ---
      final procs = ObjectBoxService.instance.procedureBox.getAll();
      final localProcNames = procs.map((p) => p.name).toSet();
      final cloudProcs =
          await FirebaseSyncService.instance.fetchCollection('procedures');
      for (var cp in cloudProcs) {
        final cloudId = cp['cloudId']?.toString();
        final name = cp['name']?.toString();
        if (cloudId != null && name != null && !localProcNames.contains(name)) {
          await FirebaseSyncService.instance.deleteDocument(
              'procedures', cloudId);
          pruneCount++;
        }
      }
      for (var p in procs) {
        await FirebaseSyncService.instance.broadcastUpdate(
            'procedures', p.toJson());
        pushCount++;
      }

      // --- 6. Mirror Doctors ---
      final doctors = ObjectBoxService.instance.doctorBox.getAll();
      final localDoctorNames = doctors.map((d) => d.name).toSet();
      final cloudDoctors = await FirebaseSyncService.instance.fetchCollection('doctors');
      for (var cd in cloudDoctors) {
        final cloudId = cd['cloudId']?.toString();
        final name = cd['name']?.toString();
        if (cloudId != null && name != null && !localDoctorNames.contains(name)) {
          await FirebaseSyncService.instance.deleteDocument('doctors', cloudId);
          pruneCount++;
        }
      }
      for (var d in doctors) {
        await FirebaseSyncService.instance.broadcastUpdate('doctors', d.toJson());
        pushCount++;
      }

      // --- 7. Mirror Appointments ---
      final appointments = ObjectBoxService.instance.appointmentBox.getAll();
      final localAppts = appointments.map((a) => a.id.toString()).toSet();
      final cloudAppts = await FirebaseSyncService.instance.fetchCollection('appointments');
      for (var ca in cloudAppts) {
        final cloudId = ca['cloudId']?.toString();
        final localId = ca['id']?.toString();
        if (cloudId != null && localId != null && !localAppts.contains(localId)) {
          await FirebaseSyncService.instance.deleteDocument('appointments', cloudId);
          pruneCount++;
        }
      }
      for (var a in appointments) {
        await FirebaseSyncService.instance.broadcastUpdate('appointments', a.toJson());
        pushCount++;
      }

      // --- 8. Mirror Prescriptions ---
      final prescriptions = ObjectBoxService.instance.prescriptionBox.getAll();
      final localScripts = prescriptions.map((p) => p.id.toString()).toSet();
      final cloudScripts = await FirebaseSyncService.instance.fetchCollection('prescriptions');
      for (var cs in cloudScripts) {
        final cloudId = cs['cloudId']?.toString();
        final localId = cs['id']?.toString();
        if (cloudId != null && localId != null && !localScripts.contains(localId)) {
          await FirebaseSyncService.instance.deleteDocument('prescriptions', cloudId);
          pruneCount++;
        }
      }
      for (var p in prescriptions) {
        await FirebaseSyncService.instance.broadcastUpdate('prescriptions', p.toJson());
        pushCount++;
      }

      // --- 9. Mirror Templates ---
      final templates = ObjectBoxService.instance.templateBox.getAll();
      final localTemplates = templates.map((t) => t.name).toSet();
      final cloudTemplates = await FirebaseSyncService.instance.fetchCollection('templates');
      for (var ct in cloudTemplates) {
        final cloudId = ct['cloudId']?.toString();
        final name = ct['name']?.toString();
        if (cloudId != null && name != null && !localTemplates.contains(name)) {
          await FirebaseSyncService.instance.deleteDocument('templates', cloudId);
          pruneCount++;
        }
      }
      for (var t in templates) {
        await FirebaseSyncService.instance.broadcastUpdate('templates', t.toJson());
        pushCount++;
      }

      debugPrint('Hub: Mirror Sync Complete. Pushed: $pushCount, Pruned: $pruneCount');
    } catch (e) {
      debugPrint('Hub: Mirror Sync error: $e');
    }
  }
}
