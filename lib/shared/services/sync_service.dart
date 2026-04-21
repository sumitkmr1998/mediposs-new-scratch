import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/medicine.dart';
import '../models/patient.dart';
import '../models/patient_image.dart';
import '../models/appointment.dart';
import '../models/doctor.dart';
import '../models/sale.dart';
import '../models/app_user.dart';
import '../models/prescription.dart';
import '../models/prescription_template.dart';
import '../models/stock_transfer.dart';
import '../services/objectbox_service.dart';
import '../services/notification_service.dart';

class SyncService extends ChangeNotifier {
  String? _hubIp;
  String? _jwtToken;
  String? _connectedRole;
  bool _isConnected = false;
  bool _isSyncing = false;

  String? get hubIp => _hubIp;
  bool get isConnected => _isConnected;
  bool get isSyncing => _isSyncing;
  String? get connectedRole => _connectedRole;

  String get _baseUrl => 'http://$_hubIp:8080';

  Future<String?> connect(String ip) async {
    try {
      final ok = await testConnection(ip);
      if (ok) {
        _hubIp = ip;
        _isConnected = true;
        // Persist the IP
        final settings = ObjectBoxService.instance.settings;
        settings.hubIp = ip;
        ObjectBoxService.instance.settingsBox.put(settings);

        notifyListeners();
        return null;
      } else {
        return 'Cannot verify Hub health at $ip.';
      }
    } catch (e) {
      return 'Cannot reach hub: $e';
    }
  }

  Future<String?> login(String pin) async {
    if (_hubIp == null) return 'No Hub IP set.';
    try {
      final url = Uri.parse('http://$_hubIp:8080/api/auth/login');
      final res = await http.post(url,
          body: jsonEncode({'pin': pin}),
          headers: {
            'content-type': 'application/json'
          }).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _jwtToken = data['token'];
        _connectedRole = data['role'];
        _isConnected = true;

        // Save the PIN so auto-connect can re-authenticate on next launch
        final settings = ObjectBoxService.instance.settings;
        settings.autoLoginPin = pin;
        ObjectBoxService.instance.settingsBox.put(settings);

        // Fetch latest settings and users upon login
        await pullSettings();
        await pullUsers();

        notifyListeners();
        return null; // success
      } else {
        return 'Invalid PIN or server error (${res.statusCode})';
      }
    } on TimeoutException {
        return 'Connection timed out. Check the IP or connection speed.';
    } catch (e) {
      return 'Authentication failed: $e';
    }
  }

  Future<bool> testConnection(String ip) async {
    try {
      final url = Uri.parse('http://$ip:8080/health');
      debugPrint('SyncService: Testing connection to $url...');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      debugPrint('SyncService: Connection test result: ${res.statusCode}');
      return res.statusCode == 200;
    } on SocketException catch (e) {
      debugPrint('SyncService: Connection test FAILED (SocketException): $e');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('SyncService: Connection test TIMED OUT after 4s: $e');
      return false;
    } catch (e) {
      debugPrint('SyncService: Connection test FAILED (Unknown Error): $e');
      return false;
    }
  }

  Future<bool> tryAutoConnect() async {
    final settings = ObjectBoxService.instance.settings;
    final savedIp = settings.hubIp;
    if (savedIp != null && savedIp.isNotEmpty) {
      debugPrint('SyncService: Attempting auto-connect to $savedIp');
      final errorMsg = await connect(savedIp);
      if (errorMsg == null) {
        // Pull users first so local login works
        await pullUsers();
        // Auto-login with the stored PIN of the first active user to get JWT token
        // This is critical: all push() methods need _jwtToken to be non-null
        final userBox = ObjectBoxService.instance.userBox;
        final users = userBox.getAll();
        if (users.isNotEmpty) {
          // Try to login using the hub PIN stored in settings (default: first user's PIN equivalent)
          // We use a special auto-login PIN approach: pull token using admin PIN from settings
          final savedPin = settings.autoLoginPin;
          if (savedPin != null && savedPin.isNotEmpty) {
            final loginErr = await login(savedPin);
            if (loginErr == null) {
              debugPrint('SyncService: Auto-login JWT obtained successfully.');
            } else {
              debugPrint(
                  'SyncService: Auto-login failed: $loginErr — push calls will fail until manual login.');
            }
          }
        }
        return true;
      }
    }
    return false;
  }

  Future<void> pullUsers() async {
    if (_hubIp == null) return;
    try {
      final url = Uri.parse('http://$_hubIp:8080/api/users');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.userBox;

        // Quick sync approach just for login:
        box.removeAll();
        debugPrint(
            'SyncService: pullUsers received ${data.length} users from Hub.');
        final users = data.map((u) {
          debugPrint(
              'SyncService Mapping User: HubId=${u['id']}, name=${u['name']}');
          return AppUser(
            id: 0, // Auto-assign local ID to avoid sequence conflicts (OBX 10002)
            name: u['name'],
            role: u['role'],
            pin: 'xxxx', // Master PIN for companion bypass
            isActive: u['isActive'] ?? true,
          );
        }).toList();

        box.putMany(users);
        debugPrint(
            'SyncService: pullUsers stored ${users.length} users in local box.');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('pullUsers err: $e');
    }
  }

  Future<void> pullMedicines() async {
    if (!_isConnected || _jwtToken == null || _isSyncing) return;
    debugPrint('SyncService: pullMedicines starting...');
    _isSyncing = true;
    notifyListeners();

    try {
      final url = Uri.parse('$_baseUrl/api/medicines');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.medicineBox;
        final allLocal = box.getAll();

        // Natural key: barcode (if non-empty), else name.
        // This avoids forcing Hub IDs which can exceed ObjectBox sequence counter on Android.
        final hubBarcodes = <String>{};
        final hubNames = <String>{};
        final claimedLocalIds = <int>{};

        for (final item in data) {
          final barcode = (item['barcode'] as String? ?? '').trim();
          final name = (item['name'] as String? ?? '').trim();
          if (barcode.isNotEmpty) hubBarcodes.add(barcode);
          hubNames.add(name);

          final updatedAt =
              DateTime.tryParse(item['updatedAt'] ?? '') ?? DateTime.now();

          // Find existing entries using normalized natural keys
          // We use list find to identify ALL matches so we can deduplicate if needed
          final matches = allLocal.where((m) {
            if (claimedLocalIds.contains(m.id)) return false;
            
            final matchesBarcode = barcode.isNotEmpty && m.barcode.trim() == barcode;
            final matchesName = m.name.trim().toLowerCase() == name.toLowerCase();
            
            return matchesBarcode || matchesName;
          }).toList();

          Medicine? existing = matches.firstOrNull;

          if (existing != null) {
            // Update the primary record
            existing
              ..name = name
              ..barcode = barcode
              ..category = item['category'] ?? 'General'
              ..unit = item['unit'] ?? 'Pcs'
              ..purchasePrice = (item['purchasePrice'] as num).toDouble()
              ..sellingPrice = (item['sellingPrice'] as num).toDouble()
              ..mainStock = item['mainStock'] ?? 0
              ..storeStock = item['storeStock'] ?? 0
              ..lowStockThreshold = item['lowStockThreshold'] ?? 10
              ..updatedAt = updatedAt;

            // Update Batches
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
            claimedLocalIds.add(existing.id);

            // DELETE Redundant records if multiple found locally
            if (matches.length > 1) {
              for (int j = 1; j < matches.length; j++) {
                final redundant = matches[j];
                debugPrint('SyncService: Deduplicating redundant locally: ${redundant.name} (ID: ${redundant.id})');
                box.remove(redundant.id);
              }
            }
          } else {
            final m = Medicine(
              id: 0, 
              name: name,
              barcode: barcode,
              category: item['category'] ?? 'General',
              unit: item['unit'] ?? 'Pcs',
              purchasePrice: (item['purchasePrice'] as num).toDouble(),
              sellingPrice: (item['sellingPrice'] as num).toDouble(),
              mainStock: item['mainStock'] ?? 0,
              storeStock: item['storeStock'] ?? 0,
              lowStockThreshold: item['lowStockThreshold'] ?? 10,
              updatedAt: updatedAt,
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
            int newId = box.put(m);
            claimedLocalIds.add(newId);
          }
        }
        // Cleanup phase: Remove locally any medicine not in Hub (deleted on Hub)
        // AND not claimed by the current sync (ensures any legacy orphans are gone)
        for (final m in allLocal) {
          if (claimedLocalIds.contains(m.id)) continue;

          final bc = m.barcode.trim();
          final matchesBar = bc.isNotEmpty && hubBarcodes.contains(bc);
          final matchesName = hubNames.any((hn) => hn.toLowerCase() == m.name.trim().toLowerCase());

          if (!matchesBar && !matchesName) {
            debugPrint('SyncService: Removing orphaned local medicine: ${m.name}');
            box.remove(m.id);
          }
        }
        debugPrint(
            'SyncService: pullMedicines synced ${data.length} medicines.');
      }
    } catch (e) {
      debugPrint('Sync Medicines error: $e');
    }

    debugPrint('SyncService: pullMedicines done.');
    _isSyncing = false;
    notifyListeners();
  }

  Future<void> pullPatients() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullPatients starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/patients');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.patientBox;
        final allLocal = box.getAll();

        // Natural key: UHID (globally unique across Hub and Android)
        final hubUhids = <String>{};
        for (final item in data) {
          final uhid = item['uhid'] as String? ?? '';
          if (uhid.isNotEmpty) hubUhids.add(uhid);
          final serverTime =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();

          final existing = allLocal.where((p) => p.uhid == uhid).firstOrNull;
          if (existing != null) {
            existing
              ..uhid = uhid
              ..name = item['name'] ?? ''
              ..phone = item['phone'] ?? ''
              ..gender = item['gender'] ?? 'Other'
              ..address = item['address'] ?? ''
              ..bloodGroup = item['bloodGroup'] ?? ''
              ..age = item['age'] ?? 0
              ..createdAt = serverTime;
            box.put(existing);
          } else {
            box.put(Patient(
              id: 0, // Auto-assign — never force Hub IDs
              uhid: uhid,
              name: item['name'] ?? '',
              phone: item['phone'] ?? '',
              gender: item['gender'] ?? 'Other',
              address: item['address'] ?? '',
              bloodGroup: item['bloodGroup'] ?? '',
              age: item['age'] ?? 0,
              createdAt: serverTime,
            ));
          }
        }
        // Remove patients deleted on Hub
        for (final p in allLocal) {
          if (p.uhid.isNotEmpty && !hubUhids.contains(p.uhid)) {
            box.remove(p.id);
          }
        }
        debugPrint('SyncService: pullPatients synced ${data.length} patients.');
      }
    } catch (e) {
      debugPrint('pullPatients err: $e');
    }
    debugPrint('SyncService: pullPatients done.');
  }

  Future<void> pullAppointments() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullAppointments starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/appointments');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.appointmentBox;
        final allLocal = box.getAll();

        // Natural key: tokenNumber + patientId + scheduledAt date (YYYY-MM-DD)
        // This uniquely identifies an appointment without relying on IDs
        String _apptKey(int token, int patientId, DateTime scheduledAt) =>
            '${token}_${patientId}_${scheduledAt.year}-${scheduledAt.month}-${scheduledAt.day}';

        final hubKeys = <String>{};
        for (final item in data) {
          final scheduledAt =
              DateTime.tryParse(item['scheduledAt'] ?? '') ?? DateTime.now();
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();
          final token = item['tokenNumber'] as int? ?? 0;
          final patientId = item['patientId'] as int? ?? 0;
          final key = _apptKey(token, patientId, scheduledAt);
          hubKeys.add(key);

          // Find existing by natural key
          final existing = allLocal
              .where((a) =>
                  _apptKey(a.tokenNumber, a.patientId, a.scheduledAt) == key)
              .firstOrNull;

          if (existing != null) {
            existing
              ..patientId = patientId
              ..patientName = item['patientName'] ?? ''
              ..patientPhone = item['patientPhone'] ?? ''
              ..doctorId = item['doctorId'] ?? 0
              ..doctorName = item['doctorName'] ?? ''
              ..tokenNumber = token
              ..status = item['status'] ?? 'waiting'
              ..consultationFee =
                  (item['consultationFee'] as num?)?.toDouble() ?? 0.0
              ..notes = item['notes'] ?? ''
              ..scheduledAt = scheduledAt
              ..createdAt = createdAt
              ..isWalkIn = item['isWalkIn'] ?? true
              ..consultationBilled = item['consultationBilled'] ?? false;
            box.put(existing);
          } else {
            box.put(Appointment(
              id: 0, // Auto-assign — never force Hub IDs
              patientId: patientId,
              patientName: item['patientName'] ?? '',
              patientPhone: item['patientPhone'] ?? '',
              doctorId: item['doctorId'] ?? 0,
              doctorName: item['doctorName'] ?? '',
              tokenNumber: token,
              status: item['status'] ?? 'waiting',
              consultationFee:
                  (item['consultationFee'] as num?)?.toDouble() ?? 0.0,
              notes: item['notes'] ?? '',
              scheduledAt: scheduledAt,
              createdAt: createdAt,
              isWalkIn: item['isWalkIn'] ?? true,
              consultationBilled: item['consultationBilled'] ?? false,
            ));
          }
        }
        // Remove appointments deleted on Hub
        for (final a in allLocal) {
          final key = _apptKey(a.tokenNumber, a.patientId, a.scheduledAt);
          if (!hubKeys.contains(key)) {
            box.remove(a.id);
          }
        }
        debugPrint(
            'SyncService: pullAppointments synced ${data.length} appointments.');
      }
    } catch (e) {
      debugPrint('pullAppointments err: $e');
    }
    debugPrint('SyncService: pullAppointments done.');
  }

  Future<void> pullDoctors() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullDoctors starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/doctors');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.doctorBox;
        final allLocal = box.getAll();

        // Natural key: doctor name
        final hubNames = <String>{};
        for (final item in data) {
          final name = item['name'] as String? ?? '';
          hubNames.add(name);
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();

          final existing = allLocal.where((d) => d.name == name).firstOrNull;
          if (existing != null) {
            existing
              ..name = name
              ..specialization = item['specialization'] ?? 'General'
              ..consultationFee =
                  (item['consultationFee'] as num?)?.toDouble() ?? 0.0
              ..qualifications = item['qualifications'] ?? ''
              ..phone = item['phone'] ?? ''
              ..isActive = item['isActive'] ?? true
              ..createdAt = createdAt;
            box.put(existing);
          } else {
            box.put(Doctor(
              id: 0, // Auto-assign
              name: name,
              specialization: item['specialization'] ?? 'General',
              consultationFee:
                  (item['consultationFee'] as num?)?.toDouble() ?? 0.0,
              qualifications: item['qualifications'] ?? '',
              phone: item['phone'] ?? '',
              isActive: item['isActive'] ?? true,
              createdAt: createdAt,
            ));
          }
        }
        // Remove doctors deleted on Hub
        for (final d in allLocal) {
          if (!hubNames.contains(d.name)) {
            box.remove(d.id);
          }
        }
        debugPrint('SyncService: pullDoctors synced ${data.length} doctors.');
      }
    } catch (e) {
      debugPrint('pullDoctors err: $e');
    }
    debugPrint('SyncService: pullDoctors done.');
  }

  Future<void> pullPrescriptions() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullPrescriptions starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/prescriptions');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.prescriptionBox;
        final allLocal = box.getAll();

        // Natural key: patientId + createdAt date (one prescripton per patient per day max)
        String _pKey(int pId, DateTime dt) =>
            '${pId}_${dt.year}-${dt.month}-${dt.day}';

        final hubKeys = <String>{};
        for (final item in data) {
          final patientId = item['patientId'] as int? ?? 0;
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();
          final key = _pKey(patientId, createdAt);
          hubKeys.add(key);

          final existing = allLocal
              .where((p) => _pKey(p.patientId, p.createdAt) == key)
              .firstOrNull;
          if (existing != null) {
            existing
              ..appointmentId = item['appointmentId'] ?? 0
              ..patientId = patientId
              ..patientName = item['patientName'] ?? ''
              ..doctorId = item['doctorId'] ?? 0
              ..doctorName = item['doctorName'] ?? ''
              ..diagnosis = item['diagnosis'] ?? ''
              ..complaints = item['complaints'] ?? ''
              ..notes = item['notes'] ?? ''
              ..itemsJson = item['itemsJson'] ?? '[]'
              ..labTestsJson = item['labTestsJson'] ?? '[]'
              ..vitalsJson = item['vitalsJson'] ?? '{}'
              ..dispensed = item['dispensed'] ?? false
              ..createdAt = createdAt;
            box.put(existing);
          } else {
            box.put(Prescription(
              id: 0, // Auto-assign
              appointmentId: item['appointmentId'] ?? 0,
              patientId: patientId,
              patientName: item['patientName'] ?? '',
              doctorId: item['doctorId'] ?? 0,
              doctorName: item['doctorName'] ?? '',
              diagnosis: item['diagnosis'] ?? '',
              complaints: item['complaints'] ?? '',
              notes: item['notes'] ?? '',
              itemsJson: item['itemsJson'] ?? '[]',
              labTestsJson: item['labTestsJson'] ?? '[]',
              vitalsJson: item['vitalsJson'] ?? '{}',
              dispensed: item['dispensed'] ?? false,
              createdAt: createdAt,
            ));
          }
        }
        // Remove prescriptions deleted on Hub
        for (final p in allLocal) {
          final key = _pKey(p.patientId, p.createdAt);
          if (!hubKeys.contains(key)) {
            box.remove(p.id);
          }
        }
        debugPrint(
            'SyncService: pullPrescriptions synced ${data.length} prescriptions.');
      }
    } catch (e) {
      debugPrint('pullPrescriptions err: $e');
    }
    debugPrint('SyncService: pullPrescriptions done.');
  }

  Future<void> pullSales() async {
    if (!_isConnected || _jwtToken == null) return;
    try {
      final url = Uri.parse('$_baseUrl/api/sales');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.saleBox;
        final allLocal = box.getAll();

        // Natural key: invoiceNo (globally unique across all devices)
        final hubInvoiceNos = <String>{};
        for (final item in data) {
          final invoiceNo = item['invoiceNo'] as String? ?? '';
          if (invoiceNo.isEmpty) continue;
          hubInvoiceNos.add(invoiceNo);
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();

          final existing =
              allLocal.where((s) => s.invoiceNo == invoiceNo).firstOrNull;
          if (existing != null) {
            existing
              ..invoiceNo = invoiceNo
              ..patientId = item['patientId'] ?? 0
              ..patientName = item['patientName'] ?? ''
              ..patientPhone = item['patientPhone'] ?? ''
              ..subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0
              ..discount = (item['discount'] as num?)?.toDouble() ?? 0
              ..taxRate = (item['taxRate'] as num?)?.toDouble() ?? 0
              ..taxAmount = (item['taxAmount'] as num?)?.toDouble() ?? 0
              ..total = (item['total'] as num?)?.toDouble() ?? 0
              ..paymentMethod = item['paymentMethod'] ?? 'cash'
              ..cashAmount = (item['cashAmount'] as num?)?.toDouble() ?? 0
              ..upiAmount = (item['upiAmount'] as num?)?.toDouble() ?? 0
              ..cardAmount = (item['cardAmount'] as num?)?.toDouble() ?? 0
              ..createdAt = createdAt
              ..synced = true
              ..isReturn = item['isReturn'] ?? false
              ..itemsJson = item['itemsJson'] ?? '[]';
            box.put(existing);
          } else {
            box.put(Sale(
              id: 0, // Auto-assign — never force Hub IDs
              invoiceNo: invoiceNo,
              patientId: item['patientId'] ?? 0,
              patientName: item['patientName'] ?? '',
              patientPhone: item['patientPhone'] ?? '',
              subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0,
              discount: (item['discount'] as num?)?.toDouble() ?? 0,
              taxRate: (item['taxRate'] as num?)?.toDouble() ?? 0,
              taxAmount: (item['taxAmount'] as num?)?.toDouble() ?? 0,
              total: (item['total'] as num?)?.toDouble() ?? 0,
              paymentMethod: item['paymentMethod'] ?? 'cash',
              cashAmount: (item['cashAmount'] as num?)?.toDouble() ?? 0,
              upiAmount: (item['upiAmount'] as num?)?.toDouble() ?? 0,
              cardAmount: (item['cardAmount'] as num?)?.toDouble() ?? 0,
              createdAt: createdAt,
              synced: true,
              isReturn: item['isReturn'] ?? false,
              itemsJson: item['itemsJson'] ?? '[]',
            ));
          }
        }
        // Remove sales voided on Hub (only remove synced=true sales not in Hub)
        for (final s in allLocal) {
          if (s.synced &&
              s.invoiceNo.isNotEmpty &&
              !hubInvoiceNos.contains(s.invoiceNo)) {
            box.remove(s.id);
          }
        }
        debugPrint('SyncService: pullSales synced ${data.length} sales.');
      }
    } catch (e) {
      debugPrint('pullSales err: $e');
    }
    debugPrint('SyncService: pullSales done.');
  }

  Future<void> pullTransfers() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullTransfers starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/transfers');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.transferBox;

        for (final item in data) {
          final existing = box.get(item['id'] ?? 0);
          final serverTime =
              DateTime.tryParse(item['transferredAt'] ?? '') ?? DateTime.now();
          if (existing == null) {
            box.put(StockTransfer(
              medicineId: item['medicineId'],
              medicineName: item['medicineName'],
              qty: item['qty'],
              fromWarehouse: item['fromWarehouse'],
              toWarehouse: item['toWarehouse'],
              transferredAt: serverTime,
              note: item['note'] ?? '',
              transferredBy: item['transferredBy'] ?? '',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('pullTransfers err: $e');
    }
    debugPrint('SyncService: pullTransfers done.');
  }

  // ─── Prescription Templates ───────────────────────────────────────────────

  Future<void> pullTemplates() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullTemplates starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/templates');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.templateBox;
        final allLocal = box.getAll();
        final hubNames = <String>{};
        for (final item in data) {
          final name = item['name'] as String? ?? '';
          if (name.isEmpty) continue;
          hubNames.add(name);
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();
          final existing = allLocal.where((t) => t.name == name).firstOrNull;
          if (existing != null) {
            existing
              ..diagnosis = item['diagnosis'] ?? ''
              ..complaints = item['complaints'] ?? ''
              ..notes = item['notes'] ?? ''
              ..itemsJson = item['itemsJson'] ?? '[]'
              ..labTestsJson = item['labTestsJson'] ?? '[]'
              ..doctorId = item['doctorId'] ?? 0
              ..createdAt = createdAt;
            box.put(existing);
          } else {
            box.put(PrescriptionTemplate(
              id: 0,
              name: name,
              diagnosis: item['diagnosis'] ?? '',
              complaints: item['complaints'] ?? '',
              notes: item['notes'] ?? '',
              itemsJson: item['itemsJson'] ?? '[]',
              labTestsJson: item['labTestsJson'] ?? '[]',
              doctorId: item['doctorId'] ?? 0,
              createdAt: createdAt,
            ));
          }
        }
        for (final t in allLocal) {
          if (!hubNames.contains(t.name)) box.remove(t.id);
        }
        debugPrint('SyncService: pullTemplates synced ${data.length} records.');
      }
    } catch (e) {
      debugPrint('pullTemplates err: $e');
    }
    debugPrint('SyncService: pullTemplates done.');
  }

  Future<bool> pushTemplate(PrescriptionTemplate t) async {
    if (_jwtToken == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/templates/push');
      final body = jsonEncode({
        'name': t.name,
        'diagnosis': t.diagnosis,
        'complaints': t.complaints,
        'notes': t.notes,
        'itemsJson': t.itemsJson,
        'labTestsJson': t.labTestsJson,
        'doctorId': t.doctorId,
        'createdAt': t.createdAt.toIso8601String(),
      });
      final res = await http
          .post(url, headers: _authHeaders(), body: body)
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('pushTemplate err: $e');
      return false;
    }
  }

  // ─── Patient Photos (lazy, per-patient) ───────────────────────────────────────────────────────

  /// Fetch photos for a specific patient (by UHID) on demand — called when
  /// the Gallery tab opens, NOT at login. Returns the list of local paths.
  /// patientLocalId = Android's local ObjectBox ID for this patient.
  Future<List<PatientImage>> pullPatientPhotosForPatient(
    String uhid,
    int patientLocalId,
  ) async {
    if (!_isConnected || _jwtToken == null) return [];
    debugPrint('SyncService: pullPatientPhotosForPatient($uhid) starting...');
    final newPhotos = <PatientImage>[];
    try {
      final url = Uri.parse('$_baseUrl/api/patient-photos')
          .replace(queryParameters: {'uhid': uhid});
      final res = await http
          .get(url, headers: _authHeaders())
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.patientImageBox;
        final allLocal = box.getAll();
        final appDocDir = await getApplicationDocumentsDirectory();

        for (final item in data) {
          final filename = item['filename'] as String? ?? '';
          final category = item['category'] as String? ?? 'General';
          final date = DateTime.tryParse(item['date'] ?? '') ?? DateTime.now();
          final imageData = item['imageData'] as String? ?? '';
          if (filename.isEmpty || imageData.isEmpty) continue;

          // Skip if already downloaded for this patient
          final alreadyExists = allLocal.any((p) =>
              p.patientId == patientLocalId &&
              p.imagePath.endsWith(filename) &&
              File(p.imagePath).existsSync());
          if (alreadyExists) continue;

          // Save image bytes
          final photoDir =
              Directory('${appDocDir.path}/patient_photos/$patientLocalId');
          if (!await photoDir.exists()) {
            await photoDir.create(recursive: true);
          }
          final savedPath = '${photoDir.path}/$filename';
          await File(savedPath).writeAsBytes(base64Decode(imageData));

          final pImage = PatientImage(
            id: 0,
            patientId: patientLocalId, // ← use Android's local ID, not Hub's
            imagePath: savedPath,
            category: category,
            date: date,
          );
          box.put(pImage);
          newPhotos.add(pImage);
        }
        debugPrint(
            'SyncService: pullPatientPhotosForPatient($uhid) — ${newPhotos.length} new photos.');
      }
    } catch (e) {
      debugPrint('pullPatientPhotosForPatient err: $e');
    }
    return newPhotos;
  }

  Future<bool> pushPatientPhoto(PatientImage photo, String patientUhid) async {
    if (_jwtToken == null) return false;
    try {
      final file = File(photo.imagePath);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      final base64Data = base64Encode(bytes);
      final filename = photo.imagePath.replaceAll('\\', '/').split('/').last;
      final url = Uri.parse('$_baseUrl/api/patient-photos/push');
      final body = jsonEncode({
        'patientUhid': patientUhid, // ← UHID-based, not internal ID
        'category': photo.category,
        'date': photo.date.toIso8601String(),
        'filename': filename,
        'imageData': base64Data,
      });
      final res = await http
          .post(url, headers: _authHeaders(), body: body)
          .timeout(const Duration(seconds: 60));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('pushPatientPhoto err: $e');
      return false;
    }
  }

  Future<bool> pushSale(Sale sale) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/sales/push');
      final body = jsonEncode({
        'invoiceNo': sale.invoiceNo,
        'patientId': sale.patientId,
        'patientName': sale.patientName,
        'patientPhone': sale.patientPhone,
        'subtotal': sale.subtotal,
        'discount': sale.discount,
        'taxRate': sale.taxRate,
        'taxAmount': sale.taxAmount,
        'total': sale.total,
        'paymentMethod': sale.paymentMethod,
        'cashAmount': sale.cashAmount,
        'upiAmount': sale.upiAmount,
        'cardAmount': sale.cardAmount,
        'createdAt': sale.createdAt.toIso8601String(),
        'synced': true,
        'isReturn': sale.isReturn,
        'itemsJson': sale.itemsJson,
      });

      debugPrint('SyncService: Pushing sale ${sale.invoiceNo} to Hub');
      final res = await http
          .post(url, headers: _authHeaders(), body: body)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        debugPrint('SyncService: Sale pushed successfully.');
        return true;
      } else {
        debugPrint('SyncService: Failed to push sale - HTTP ${res.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('SyncService: pushSale err: $e');
      return false;
    }
  }

  Future<bool> pushPatient(Patient p) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/patients/push');
      final body = jsonEncode({
        'uhid': p.uhid,
        'name': p.name,
        'phone': p.phone,
        'gender': p.gender,
        'address': p.address,
        'bloodGroup': p.bloodGroup,
        'age': p.age,
        'createdAt': p.createdAt.toIso8601String(),
      });

      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushPatient err: $e');
      return false;
    }
  }

  Future<bool> pushAppointment(Appointment a) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/appointments/push');
      final body = jsonEncode({
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
      });

      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushAppointment err: $e');
      return false;
    }
  }

  Future<bool> pushDoctor(Doctor d) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/doctors/push');
      final body = jsonEncode({
        'id': d.id,
        'name': d.name,
        'specialization': d.specialization,
        'consultationFee': d.consultationFee,
        'qualifications': d.qualifications,
        'phone': d.phone,
        'isActive': d.isActive,
        'createdAt': d.createdAt.toIso8601String(),
      });

      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushDoctor err: $e');
      return false;
    }
  }

  Future<bool> pushDoctorDelete(int id) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/doctors/delete');
      final body = jsonEncode({'id': id});
      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushDoctorDelete err: $e');
      return false;
    }
  }

  Future<bool> pushPatientDelete(int id) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/patients/delete');
      final body = jsonEncode({'id': id});
      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushPatientDelete err: $e');
      return false;
    }
  }

  Future<bool> pushMedicineDelete(int id) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/medicines/delete');
      final body = jsonEncode({'id': id});
      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushMedicineDelete err: $e');
      return false;
    }
  }

  Future<bool> pushPrescriptionDelete(int id) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/prescriptions/delete');
      final body = jsonEncode({'id': id});
      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushPrescriptionDelete err: $e');
      return false;
    }
  }

  Future<bool> pushPrescription(Prescription p) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/prescriptions/push');
      final body = jsonEncode({
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
      });

      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushPrescription err: $e');
      return false;
    }
  }

  Future<bool> pushTransfer(StockTransfer t) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/transfers/push');
      final body = jsonEncode({
        'medicineId': t.medicineId,
        'medicineName': t.medicineName,
        'qty': t.qty,
        'fromWarehouse': t.fromWarehouse,
        'toWarehouse': t.toWarehouse,
        'transferredAt': t.transferredAt.toIso8601String(),
        'note': t.note,
        'transferredBy': t.transferredBy,
      });

      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushTransfer err: $e');
      return false;
    }
  }

  Future<bool> pushMedicine(Medicine m) async {
    if (_hubIp == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/medicines/push');
      final body = jsonEncode({
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
                  'id': 0, // Let server assign
                  'batchNo': b.batchNo,
                  'expiryDate': b.expiryDate.toIso8601String(),
                  'mainStock': b.mainStock,
                  'storeStock': b.storeStock,
                })
            .toList(),
      });

      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushMedicine err: $e');
      return false;
    }
  }

  void disconnect() {
    _isConnected = false;
    _hubIp = null;
    _jwtToken = null;
    _connectedRole = null;

    // Clear persisted IP
    final settings = ObjectBoxService.instance.settings;
    settings.hubIp = null;
    ObjectBoxService.instance.settingsBox.put(settings);

    notifyListeners();
  }

  Map<String, String> _authHeaders() => {
        'Authorization': 'Bearer $_jwtToken',
        'Content-Type': 'application/json',
      };

  Future<void> pullSettings() async {
    if (!_isConnected || _jwtToken == null) return;
    try {
      final url = Uri.parse('$_baseUrl/api/settings');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final box = ObjectBoxService.instance.settingsBox;
        final current = ObjectBoxService.instance.settings;
        
        final updated = AppSettings.fromJson(data);
        updated.id = current.id;
        // Keep local-only settings
        updated.hubIp = current.hubIp;
        updated.autoLoginPin = current.autoLoginPin;
        updated.serverPort = current.serverPort;
        updated.jwtSecret = current.jwtSecret;

        box.put(updated);
        notifyListeners();
        debugPrint('SyncService: pullSettings completed.');
      }
    } catch (e) {
      debugPrint('SyncService: pullSettings err: $e');
    }
  }

  Future<bool> pushUser(AppUser user) async {
    if (!_isConnected || _jwtToken == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/users/push');
      final body = jsonEncode(user.toJson());
      final res = await http.post(url, headers: _authHeaders(), body: body);
      debugPrint('SyncService: pushUser result=${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushUser err: $e');
      return false;
    }
  }

  Future<bool> pushSettings(AppSettings settings) async {
    if (!_isConnected || _jwtToken == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/settings/push');
      final body = jsonEncode(settings.toJson());
      final res = await http.post(url, headers: _authHeaders(), body: body);
      debugPrint('SyncService: pushSettings result=${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushSettings err: $e');
      return false;
    }
  }
}

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _connected = false;
  String? _lastIp;
  bool _intentionalDisconnect = false;
  final List<Map<String, dynamic>> _events = [];

  bool get connected => _connected;
  List<Map<String, dynamic>> get events => List.unmodifiable(_events);

  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  void connect(String ip) {
    _lastIp = ip;
    _intentionalDisconnect = false;
    _doConnect(ip);
  }

  void _doConnect(String ip) {
    if (_connected) return;
    try {
      final uri = Uri.parse('ws://$ip:8080/ws/updates');
      _channel = WebSocketChannel.connect(uri);
      _connected = true;
      debugPrint('WebSocketService: Connected to $ip');

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            _events.insert(0, msg);
            _eventController.add(msg);

            // Notification logic
            if (msg['event'] == 'new_patient') {
              NotificationService.instance.showNotification(
                id: DateTime.now().millisecond,
                title: 'New Patient in Queue',
                body: msg['patientName'] ?? 'A new patient has been added.',
              );
            } else if (msg['event'] == 'low_stock') {
              NotificationService.instance.showNotification(
                id: 1001,
                title: 'Low Stock Alert',
                body: msg['medicineName'] ??
                    'One or more items are low in stock.',
              );
            } else if (msg['event'] == 'remote_camera_trigger') {
              NotificationService.instance.showNotification(
                id: 2001,
                title: 'Remote Camera Requested',
                body: 'Doctor needs a photo of ${msg['patientName'] ?? 'Patient'}. Tap to open camera.',
                payload: jsonEncode({
                  'type': 'remote_camera',
                  'patientUhid': msg['patientUhid'],
                  'patientName': msg['patientName'],
                  'hubIp': msg['hubIp'],
                }),
              );
            }

            notifyListeners();
          } catch (_) {}
        },
        onDone: () {
          _connected = false;
          notifyListeners();
          debugPrint('WebSocketService: Connection closed.');
          if (!_intentionalDisconnect && _lastIp != null) {
            _scheduleReconnect();
          }
        },
        onError: (e) {
          _connected = false;
          notifyListeners();
          debugPrint('WebSocketService: Error: $e');
          if (!_intentionalDisconnect && _lastIp != null) {
            _scheduleReconnect();
          }
        },
      );
      notifyListeners();
    } catch (e) {
      debugPrint('WebSocketService: Connect failed: $e');
      _connected = false;
      if (!_intentionalDisconnect && _lastIp != null) {
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    debugPrint('WebSocketService: Scheduling reconnect in 5s...');
    Future.delayed(const Duration(seconds: 5), () {
      if (!_intentionalDisconnect && _lastIp != null && !_connected) {
        debugPrint('WebSocketService: Attempting reconnect to $_lastIp');
        _doConnect(_lastIp!);
      }
    });
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _channel?.sink.close();
    _connected = false;
    _lastIp = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _intentionalDisconnect = true;
    _eventController.close();
    super.dispose();
  }
}
