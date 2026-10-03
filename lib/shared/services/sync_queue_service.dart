import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'objectbox_service.dart';
import '../models/sync_queue_item.dart';
import '../models/attendance_record.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../models/appointment.dart';
import '../models/doctor.dart';
import '../models/prescription.dart';
import '../models/audit_log.dart';
import '../models/stock_transfer.dart';
import '../models/purchase_record.dart';
import '../models/medicine.dart';
import '../models/prescription_template.dart';
import '../models/procedure.dart';
import '../models/schedule_h1_record.dart';
import '../models/app_user.dart';
import 'sync_service.dart';
import 'sync/outbox_drain.dart';
import '../../objectbox.g.dart';

class SyncQueueService extends ChangeNotifier {
  static final SyncQueueService instance = SyncQueueService._();
  SyncQueueService._();

  bool _isProcessing = false;
  bool _needsDrain = false;
  Timer? _syncTimer;

  void init() {
    debugPrint('SyncQueueService: Initializing...');
    if (SyncService.instance.isHub) {
      debugPrint('SyncQueueService: Device is Windows Hub (Server). Client outbox timer disabled.');
      return;
    }
    _startAutoSync();
    processQueue(); // Run once at start
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) => processQueue());
  }

  Future<void> addToQueue({
    required String entity,
    required String action,
    required Map<String, dynamic> data,
  }) async {
    // Windows Hub is the central server and does not push to its own outbox queue
    if (SyncService.instance.isHub) {
      return;
    }

    enqueue(entity: entity, action: action, data: data);
    processQueue();
  }

  /// Synchronous persistence so callers can include an outbox row in their
  /// entity write transaction. Network work starts only after that commit.
  void enqueue({
    required String entity,
    required String action,
    required Map<String, dynamic> data,
  }) {
    if (SyncService.instance.isHub) return;
    final item = SyncQueueItem(
      entity: entity,
      action: action,
      dataJson: jsonEncode(data),
      timestamp: DateTime.now(),
    );
    ObjectBoxService.instance.syncQueueBox.put(item);
    debugPrint('SyncQueueService: Added $action for $entity to queue.');
  }

  Future<void> processQueue() async {
    if (SyncService.instance.isHub) return;
    if (_isProcessing) {
      _needsDrain = true;
      return;
    }
    _isProcessing = true;

    bool queueFailed = false;
    try {
      final box = ObjectBoxService.instance.syncQueueBox;
      
      _needsDrain = false;
      final query = box.query(SyncQueueItem_.processed.equals(false))
          .order(SyncQueueItem_.timestamp)
          .order(SyncQueueItem_.id)
          .build();
      final List<SyncQueueItem> items;
      try {
        items = query.find();
      } finally {
        query.close();
      }
      queueFailed = await OutboxDrain.run(
        items: items,
        push: _pushItem,
        save: (item) => box.put(item),
        now: DateTime.now,
      );
      // Automatically prune processed items older than 24 hours to prevent DB bloat
      _pruneProcessedItems();
    } catch (e) {
      debugPrint('SyncQueueService error: $e');
      queueFailed = true;
    } finally {
      _isProcessing = false;
      SyncService.instance.setQueueSyncFailed(queueFailed);
      notifyListeners();
      if (_needsDrain && !queueFailed) {
        processQueue();
      }
    }
  }

  /// Removes processed items older than 24 hours to keep the ObjectBox store clean and fast.
  void _pruneProcessedItems() {
    try {
      final box = ObjectBoxService.instance.syncQueueBox;
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final processedItems = box.query(SyncQueueItem_.processed.equals(true))
          .build()
          .find();
      
      final toRemoveIds = <int>[];
      for (final item in processedItems) {
        if (item.timestamp.isBefore(cutoff)) {
          toRemoveIds.add(item.id);
        }
      }
      if (toRemoveIds.isNotEmpty) {
        box.removeMany(toRemoveIds);
        debugPrint('SyncQueueService: Pruned ${toRemoveIds.length} processed items older than 24h.');
      }
    } catch (e) {
      debugPrint('SyncQueueService: Error pruning processed items: $e');
    }
  }

  Future<bool> _pushItem(SyncQueueItem item) async {
    final syncService = SyncService.instance;
    final data = jsonDecode(item.dataJson);

    try {
      switch (item.entity) {
        case 'patient':
          if (item.action == 'delete') {
            return await syncService.pushPatientDelete(data['uhid'] ?? '');
          }
          return await syncService.pushPatient(Patient.fromJson(data), action: item.action);
        case 'medicine':
          if (item.action == 'create' || item.action == 'update') {
            return await syncService.pushMedicine(Medicine.fromJson(data));
          }
          if (item.action == 'delete') {
            return await syncService.pushMedicineDelete(
                data['barcode'] ?? '', data['name'] ?? '');
          }
          break;
        case 'sale':
          if (item.action == 'create' || item.action == 'update') {
            return await syncService.pushSale(Sale.fromJson(data));
          }
          if (item.action == 'delete') {
            return await syncService.pushSaleDelete(data['invoiceNo'] ?? '');
          }
          break;
        case 'h1_record':
          if (item.action == 'create') {
            return await syncService.pushH1Record(ScheduleH1Record.fromJson(data));
          }
          break;
        case 'appointment':
          return await syncService.pushAppointment(Appointment.fromJson(data));
        case 'doctor':
          if (item.action == 'delete') {
            return await syncService.pushDoctorDelete(
              data['id'] as int? ?? 0,
              name: data['name'] as String?,
            );
          }
          return await syncService.pushDoctor(Doctor.fromJson(data));
        case 'prescription':
          if (item.action == 'delete') {
            return await syncService.pushPrescriptionDelete(
              data['id'] as int? ?? 0,
              uhid: data['patientUhid'] as String?,
              createdAtStr: data['createdAt'] as String?,
            );
          }
          return await syncService.pushPrescription(Prescription.fromJson(data));
        case 'transfer':
          return await syncService.pushTransfer(StockTransfer.fromJson(data));
        case 'purchase':
          return await syncService.pushPurchase(PurchaseRecord.fromJson(data));
        case 'audit_log':
          return await syncService.pushAuditLog(AuditLog.fromJson(data));
        case 'template':
          if (item.action == 'delete') return await syncService.pushTemplateDelete(data['name']);
          return await syncService.pushTemplate(PrescriptionTemplate.fromJson(data));
        case 'photo':
          if (item.action == 'delete') return await syncService.pushPatientPhotoDelete(data['uhid'], data['fileName']);
          final patient = ObjectBoxService.instance.patientBox.get(data['patientId']);
          final uhid = data['uhid'] as String? ?? patient?.uhid ?? '';
          if (uhid.isEmpty) return true;
          final photo = ObjectBoxService.instance.patientImageBox.get(data['id']);
          if (photo == null) return true;
          return await syncService.pushPatientPhoto(photo, uhid);
        case 'procedure':
          if (item.action == 'delete') {
            return await syncService.pushProcedureDelete(data['name'] ?? '');
          }
          return await syncService.pushProcedure(Procedure.fromJson(data));
        case 'procedure_record':
          return await syncService.pushProcedureRecord(ProcedureRecord.fromJson(data));
        case 'attendance':
          if (item.action == 'delete') {
            return await syncService.pushAttendanceDelete(data['userId'], data['date']);
          }
          return await syncService.pushAttendance(AttendanceRecord.fromJson(data));
        case 'user':
          return await syncService.pushUser(AppUser.fromJson(data));
        case 'settings':
          return await syncService.pushSettings(AppSettings.fromJson(data));
        default:
          throw FormatException('Unsupported outbox entity: ' + item.entity);
      }
      throw FormatException('Unsupported outbox action');
    } on FormatException {
      rethrow;
    } catch (e) {
      debugPrint('SyncQueueService: Error pushing ${item.entity}: $e');
      return false;
    }
  }
}

