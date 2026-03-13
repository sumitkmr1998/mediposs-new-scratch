import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    router.post('/api/sync', _withAuth(_syncHandler));

    // ------ WebSocket ------
    router.get('/ws/updates', webSocketHandler(_onWsConnect));

    final pipeline = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    _server = await io.serve(pipeline, InternetAddress.anyIPv4, _port);
    // Print statement removed for production lint: print('🟢 MediPoss Hub running on port $_port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // Broadcast a JSON message to all connected WS clients
  void broadcast(Map<String, dynamic> message) {
    final data = jsonEncode(message);
    for (final client in _wsClients.toList()) {
      try {
        client.sink.add(data);
      } catch (_) {
        _wsClients.remove(client);
      }
    }
  }

  void _onWsConnect(WebSocketChannel channel) {
    _wsClients.add(channel);
    channel.stream.listen(
      (_) {},
      onDone: () => _wsClients.remove(channel),
      onError: (_) => _wsClients.remove(channel),
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

    final users = ObjectBoxService.instance.userBox.getAll();
    debugPrint(
        'Hub: login attempt for PIN $pin. Total users in DB: ${users.length}');
    final user = users.cast<AppUser?>().firstWhere(
          (u) => u!.pin == pin && u.isActive,
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
      jsonEncode({'token': token, 'role': user.role, 'name': user.name}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _usersGetHandler(Request req) {
    final users = ObjectBoxService.instance.userBox.getAll();
    debugPrint('Hub: Serving ${users.length} total users to client.');
    // Only return public info, never the PIN.
    final json = users.where((u) => u.isActive).map((u) {
      debugPrint('Hub User: id=${u.id}, name=${u.name}, role=${u.role}');
      return {
        'id': u.id,
        'name': u.name,
        'role': u.role,
        'isActive': u.isActive,
      };
    }).toList();

    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _medicinesGetHandler(Request req) {
    final medicines = ObjectBoxService.instance.medicineBox.getAll();
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
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _medicinesSyncHandler(Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final list = (body['medicines'] as List?) ?? [];
    int upserted = 0;

    for (final item in list) {
      final existing =
          ObjectBoxService.instance.medicineBox.get(item['id'] ?? 0);
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
            ..storeStock = item['storeStock'];
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
          updatedAt: DateTime.tryParse(item['updatedAt'] ?? ''),
        );
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
      final id = item['id'] as int? ?? 0;
      final existing = id > 0 ? box.get(id) : null;

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
          ..updatedAt = DateTime.now();
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
        );
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
    final sales = ObjectBoxService.instance.saleBox.getAll();
    final json = sales
        .map((s) => {
              'id': s.id,
              'invoiceNo': s.invoiceNo,
              'patientId': s.patientId,
              'patientName': s.patientName,
              'patientPhone': s.patientPhone,
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
              'synced': s.synced,
              'isReturn': s.isReturn,
              'itemsJson': s.itemsJson,
            })
        .toList();
    return Response.ok(
      jsonEncode({'data': json}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _salesPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;

      final sale = Sale(
        invoiceNo: body['invoiceNo'] ?? '',
        patientId: body['patientId'] ?? 0,
        patientName: body['patientName'] ?? '',
        patientPhone: body['patientPhone'] ?? '',
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
        itemsJson: body['itemsJson'] ?? '[]',
      );

      // Save sale to Hub DB
      ObjectBoxService.instance.saleBox.put(sale);

      // Deduct inventory on Hub
      final list = jsonDecode(sale.itemsJson) as List;
      for (final jsonItem in list) {
        final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
        // Use natural key (medicineName) to find the medicine on the Hub safely
        final m = ObjectBoxService.instance.medicineBox
            .getAll()
            .where((x) => x.name == item.medicineName)
            .firstOrNull;

        if (m != null) {
          if (sale.isReturn) {
            m.storeStock = (m.storeStock - item.qty.toInt()).clamp(
                0, 999999); // Note: qty is negative for returns in SaleItem
          } else {
            m.storeStock = (m.storeStock - item.qty.toInt()).clamp(0, 999999);
          }
          m.updatedAt = DateTime.now();
          ObjectBoxService.instance.medicineBox.put(m);
        }
      }

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
        p.id = existing.id;
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
      // 1. Resolve correct patient ID on Hub by Name and Phone
      int hubPatientId = 0;
      final pName = body['patientName'] ?? '';
      final pPhone = body['patientPhone'] ?? '';
      if (pName.isNotEmpty) {
        final p = ObjectBoxService.instance.patientBox
                .getAll()
                .where((p) => p.name == pName && p.phone == pPhone)
                .firstOrNull ??
            ObjectBoxService.instance.patientBox
                .getAll()
                .where((p) => p.name == pName)
                .firstOrNull;
        if (p != null) hubPatientId = p.id;
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
    final patients = ObjectBoxService.instance.patientBox.getAll();
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
            })
        .toList();
    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _appointmentsGetHandler(Request req) {
    final appointments = ObjectBoxService.instance.appointmentBox.getAll();
    final json = appointments
        .map((a) => {
              'id': a.id,
              'patientId': a.patientId,
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
            })
        .toList();
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
    final prescriptions = ObjectBoxService.instance.prescriptionBox.getAll();
    final json = prescriptions
        .map((p) => {
              'id': p.id,
              'appointmentId': p.appointmentId,
              'patientId': p.patientId,
              'patientName': p.patientName,
              'doctorId': p.doctorId,
              'doctorName': p.doctorName,
              'diagnosis': p.diagnosis,
              'complaints': p.complaints,
              'notes': p.notes,
              'itemsJson': p.itemsJson,
              'labTestsJson': p.labTestsJson,
              'vitalsJson': p.vitalsJson,
              'dispensed': p.dispensed,
              'createdAt': p.createdAt.toIso8601String(),
            })
        .toList();
    return Response.ok(
      jsonEncode({'data': json, 'count': json.length}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _prescriptionsPushHandler(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final p = Prescription(
        appointmentId: body['appointmentId'] ?? 0,
        patientId: body['patientId'] ?? 0,
        patientName: body['patientName'] ?? '',
        doctorId: body['doctorId'] ?? 0,
        doctorName: body['doctorName'] ?? '',
        diagnosis: body['diagnosis'] ?? '',
        complaints: body['complaints'] ?? '',
        notes: body['notes'] ?? '',
        itemsJson: body['itemsJson'] ?? '[]',
        labTestsJson: body['labTestsJson'] ?? '[]',
        vitalsJson: body['vitalsJson'] ?? '{}',
        dispensed: body['dispensed'] ?? false,
        createdAt: DateTime.tryParse(body['createdAt'] ?? '') ?? DateTime.now(),
      );

      // Use natural key mapping to prevent local sequence collisions
      final existing = ObjectBoxService.instance.prescriptionBox
          .getAll()
          .where((x) =>
              x.patientName == p.patientName &&
              x.createdAt.year == p.createdAt.year &&
              x.createdAt.month == p.createdAt.month &&
              x.createdAt.day == p.createdAt.day)
          .firstOrNull;

      if (existing != null) {
        p.id = existing.id;
        // Fix up foreign keys in case they were Android-local IDs
        p.appointmentId = existing.appointmentId;
        p.patientId = existing.patientId;
        p.doctorId = existing.doctorId;
      } else {
        p.id = 0;

        // Let's resolve correct hub IDs
        final hubPatient = ObjectBoxService.instance.patientBox
            .getAll()
            .where((x) => x.name == p.patientName)
            .firstOrNull;
        if (hubPatient != null) p.patientId = hubPatient.id;

        final hubDoctor = ObjectBoxService.instance.doctorBox
            .getAll()
            .where((x) => x.name == p.doctorName)
            .firstOrNull;
        if (hubDoctor != null) p.doctorId = hubDoctor.id;
      }

      ObjectBoxService.instance.prescriptionBox.put(p);

      // Also ensure appointment status is updated to pharmacy if it was with_doctor
      // Resolve Hub appointment by natural key
      final appt = ObjectBoxService.instance.appointmentBox
          .getAll()
          .where((x) =>
              x.patientName == p.patientName &&
              x.scheduledAt.year == p.createdAt.year &&
              x.scheduledAt.month == p.createdAt.month &&
              x.scheduledAt.day == p.createdAt.day)
          .firstOrNull;

      if (appt != null && appt.status == kStatusWithDoctor) {
        appt.status = kStatusPharmacy;
        ObjectBoxService.instance.appointmentBox.put(appt);
      }

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
      if (id != null && id > 0) {
        ObjectBoxService.instance.patientBox.remove(id);
        broadcast({'event': 'sync_received'});
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
      if (id != null && id > 0) {
        ObjectBoxService.instance.medicineBox.remove(id);
        broadcast({'event': 'medicines_updated'});
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
      jsonEncode({'data': json}),
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

      broadcast({'event': 'sync_received'});
      _incomingDataController.add('patient_photos');

      return Response.ok(
        jsonEncode({'status': 'success'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      debugPrint('Hub: Patient Photos Push Err: $e');
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
}
