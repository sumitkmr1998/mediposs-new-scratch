import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'objectbox_service.dart';
import '../models/sync_queue_item.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../models/appointment.dart';
import '../models/doctor.dart';
import '../models/prescription.dart';
import '../models/audit_log.dart';
import '../models/stock_transfer.dart';
import '../models/medicine.dart';
import '../models/prescription_template.dart';
import '../models/procedure.dart';
import '../models/schedule_h1_record.dart';
import 'sync_service.dart';
import '../../objectbox.g.dart';

class SyncQueueService extends ChangeNotifier {
  static final SyncQueueService instance = SyncQueueService._();
  SyncQueueService._();

  bool _isProcessing = false;
  Timer? _syncTimer;

  void init() {
    debugPrint('SyncQueueService: Initializing...');
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
    final item = SyncQueueItem(
      entity: entity,
      action: action,
      dataJson: jsonEncode(data),
      timestamp: DateTime.now(),
    );
    ObjectBoxService.instance.syncQueueBox.put(item);
    debugPrint('SyncQueueService: Added $action for $entity to queue.');
    processQueue();
  }

  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    bool queueFailed = false;
    try {
      final box = ObjectBoxService.instance.syncQueueBox;
      
      while (true) {
        final items = box.query(SyncQueueItem_.processed.equals(false))
            .order(SyncQueueItem_.timestamp)
            .build()
            .find();
        
        if (items.isEmpty) break;

        debugPrint('SyncQueueService: Processing ${items.length} items...');
        bool hasFailed = false;
        
        for (final item in items) {
          final ok = await _pushItem(item);
          if (ok) {
            item.processed = true;
            box.put(item);
            debugPrint('SyncQueueService: Successfully synced ${item.entity} (${item.action})');
          } else {
            if (item.entity == 'photo') {
              debugPrint('SyncQueueService: Failed to sync photo. Skipping to next item to avoid blocking queue.');
              continue;
            }
            debugPrint('SyncQueueService: Failed to sync ${item.entity}. Pausing queue.');
            hasFailed = true;
            break; // Stop on first failure to maintain order
          }
        }
        
        if (hasFailed) {
          queueFailed = true;
          break; // Stop outer loop if an item failed
        }
      }
    } catch (e) {
      debugPrint('SyncQueueService error: $e');
      queueFailed = true;
    } finally {
      _isProcessing = false;
      SyncService.instance.setQueueSyncFailed(queueFailed);
      notifyListeners();
    }
  }

  Future<bool> _pushItem(SyncQueueItem item) async {
    final syncService = SyncService.instance;
    final data = jsonDecode(item.dataJson);

    try {
      switch (item.entity) {
        case 'patient':
          if (item.action == 'delete')
            return await syncService.pushPatientDelete(data['uhid'] ?? '');
          return await syncService.pushPatient(Patient.fromJson(data));
        case 'medicine':
          if (item.action == 'create')
            return await syncService.pushMedicine(Medicine.fromJson(data));
          if (item.action == 'update')
            return await syncService.pushMedicine(Medicine.fromJson(data));
          if (item.action == 'delete')
            return await syncService.pushMedicineDelete(
                data['barcode'] ?? '', data['name'] ?? '');
          break;
        case 'sale':
          if (item.action == 'create')
            return await syncService.pushSale(Sale.fromJson(data));
          if (item.action == 'delete')
            return await syncService.pushSaleDelete(data['invoiceNo'] ?? '');
          break;
        case 'h1_record':
          if (item.action == 'create')
            return await syncService.pushH1Record(ScheduleH1Record.fromJson(data));
          break;
        case 'appointment':
          return await syncService.pushAppointment(Appointment.fromJson(data));
        case 'doctor':
          if (item.action == 'delete') return await syncService.pushDoctorDelete(data['id']);
          return await syncService.pushDoctor(Doctor.fromJson(data));
        case 'prescription':
          if (item.action == 'delete') return await syncService.pushPrescriptionDelete(data['id']);
          return await syncService.pushPrescription(Prescription.fromJson(data));
        case 'transfer':
          return await syncService.pushTransfer(StockTransfer.fromJson(data));
        case 'audit_log':
          try {
            final ok = await syncService.pushAuditLog(AuditLog.fromJson(data));
            if (!ok) {
              debugPrint('SyncQueueService: Failed to push audit log, but skipping to avoid blocking queue.');
            }
          } catch (e) {
            debugPrint('SyncQueueService: Error pushing audit log: $e');
          }
          return true; // Never block queue on audit log sync failure
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
          if (item.action == 'delete')
            return await syncService.pushProcedureDelete(data['name'] ?? '');
          return await syncService.pushProcedure(Procedure.fromJson(data));
        default:
          return true; // Ignore unknown entities
      }
      return false;
    } catch (e) {
      debugPrint('SyncQueueService: Error pushing ${item.entity}: $e');
      return false;
    }
  }
}
