import 'package:flutter/material.dart';
import '../models/appointment.dart';
import '../models/patient.dart';
import '../models/doctor.dart';
import '../models/app_user.dart';
import '../models/sale.dart';
import '../services/objectbox_service.dart';
import '../services/time_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/firebase_sync_service.dart';
import '../services/audit_service.dart';
import 'dart:io';
import 'dart:convert';
import 'sales_provider.dart';
import '../../objectbox.g.dart';

enum OpdFilter { today, yesterday, last7Days, allTime, custom }

class OpdProvider extends ChangeNotifier {
  List<Appointment> _appointments = [];
  List<Doctor> _doctors = [];

  OpdFilter _activeFilter = OpdFilter.today;
  DateTime? _customStart;
  DateTime? _customEnd;

  List<Appointment> get appointments => _appointments;
  List<Doctor> get doctors => _doctors;
  List<Doctor> get activeDoctors => _doctors.where((d) => d.isActive).toList();

  OpdFilter get activeFilter => _activeFilter;
  DateTime? get customStart => _customStart;
  DateTime? get customEnd => _customEnd;

  List<Appointment> get todayQueue {
    final today = DateTime.now();
    return _appointments
        .where((a) {
          final localSched = a.scheduledAt.toLocal();
          return localSched.year == today.year &&
              localSched.month == today.month &&
              localSched.day == today.day &&
              a.status != kStatusCancelled;
        })
        .toList()
      ..sort((a, b) => a.tokenNumber.compareTo(b.tokenNumber));
  }

  List<Appointment> get filteredQueue {
    return _appointments.where((a) {
      if (a.status == kStatusCancelled) return false;

      final dt = a.scheduledAt;
      if (_customStart != null && _customEnd != null) {
        return dt.isAfter(_customStart!.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(_customEnd!.add(const Duration(seconds: 1)));
      }
      return true;
    }).toList()
      ..sort((a, b) => a.tokenNumber.compareTo(b.tokenNumber));
  }

  int get filteredPatientCount => filteredQueue.length;
  int get filteredDoneCount =>
      filteredQueue.where((a) => a.status == kStatusDone).length;
  double get filteredConsultationRevenue =>
      filteredQueue.fold(0.0, (sum, a) => sum + a.consultationFee);

  Duration get filteredAverageWaitingTime {
    final list = filteredQueue.where((a) => a.calledAt != null).toList();
    if (list.isEmpty) return Duration.zero;
    final totalMs = list.fold(0, (sum, a) {
      final diff = a.calledAt!.difference(a.createdAt).inMilliseconds;
      return sum + (diff > 0 ? diff : 0);
    });
    return Duration(milliseconds: (totalMs / list.length).round());
  }

  Duration get filteredAverageDoctorTime {
    final list = filteredQueue
        .where((a) => a.calledAt != null && (a.pharmacyAt != null || a.completedAt != null))
        .toList();
    if (list.isEmpty) return Duration.zero;
    final totalMs = list.fold(0, (sum, a) {
      final end = a.pharmacyAt ?? a.completedAt!;
      final diff = end.difference(a.calledAt!).inMilliseconds;
      return sum + (diff > 0 ? diff : 0);
    });
    return Duration(milliseconds: (totalMs / list.length).round());
  }

  double get filteredCollectedRevenue => filteredQueue
      .where((a) => a.paymentMethod != 'pending')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  double get filteredCashRevenue => filteredQueue
      .where((a) => a.paymentMethod.toLowerCase() == 'cash')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  double get filteredUpiRevenue => filteredQueue
      .where((a) => a.paymentMethod.toLowerCase() == 'upi')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  double get filteredCardRevenue => filteredQueue
      .where((a) => a.paymentMethod.toLowerCase() == 'card')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  // Today-specific totals for restricted Dashboard views
  double get todayCollectedRevenue => todayQueue
      .where((a) => a.paymentMethod != 'pending')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  double get todayCashRevenue => todayQueue
      .where((a) => a.paymentMethod.toLowerCase() == 'cash')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  double get todayUpiRevenue => todayQueue
      .where((a) => a.paymentMethod.toLowerCase() == 'upi')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  double get todayCardRevenue => todayQueue
      .where((a) => a.paymentMethod.toLowerCase() == 'card')
      .fold(0.0, (sum, a) => sum + a.consultationFee);

  int get todayPatientCount => todayQueue.length;

  static const int pageSize = 30;
  int _loadedCount = 30;

  List<Appointment> get displayedQueue =>
      filteredQueue.take(_loadedCount).toList();
  bool get hasMore => _loadedCount < filteredQueue.length;

  void loadMore() {
    if (!hasMore) return;
    _loadedCount = (_loadedCount + pageSize).clamp(0, filteredQueue.length);
    notifyListeners();
  }

  OpdProvider() {
    _setToday();
  }

  void _setToday() {
    final now = DateTime.now();
    _customStart = DateTime(now.year, now.month, now.day);
    _customEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  void setFilter(OpdFilter filter, {DateTimeRange? range}) {
    _activeFilter = filter;
    final now = DateTime.now();

    switch (filter) {
      case OpdFilter.today:
        _setToday();
        break;
      case OpdFilter.yesterday:
        final yest = now.subtract(const Duration(days: 1));
        _customStart = DateTime(yest.year, yest.month, yest.day);
        _customEnd = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
        break;
      case OpdFilter.last7Days:
        final start = now.subtract(const Duration(days: 6));
        _customStart = DateTime(start.year, start.month, start.day);
        _customEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case OpdFilter.allTime:
        _customStart = null;
        _customEnd = null;
        break;
      case OpdFilter.custom:
        if (range != null) {
          _customStart = range.start;
          _customEnd = DateTime(
            range.end.year,
            range.end.month,
            range.end.day,
            23,
            59,
            59,
          );
        }
        break;
    }
    _loadedCount = pageSize;
    notifyListeners();
  }

  void loadAll() {
    final db = ObjectBoxService.instance;
    _appointments = db.appointmentBox.getAll()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    _doctors = db.doctorBox.getAll()..sort((a, b) => a.name.compareTo(b.name));
    _loadedCount = pageSize;
    notifyListeners();
  }

  int _nextTokenForToday() {
    final today = DateTime.now();
    final todayAppts = _appointments.where((a) =>
        a.scheduledAt.year == today.year &&
        a.scheduledAt.month == today.month &&
        a.scheduledAt.day == today.day);
    if (todayAppts.isEmpty) return 1;
    return todayAppts
            .map((a) => a.tokenNumber)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  Future<Appointment> createAppointment({
    required int patientId,
    required String patientName,
    String patientPhone = '',
    required int doctorId,
    required String doctorName,
    required double consultationFee,
    required String paymentMethod,
    DateTime? scheduledAt,
    bool isWalkIn = true,
    SyncService? syncService,
    AppUser? actor,
    SalesProvider? salesProvider,
  }) async {
    final robustNow = await TimeService.getRobustTime();
    
    // Prevent double-booking from rapid button clicking or client sync latency
    final tenSecondsAgo = robustNow.subtract(const Duration(seconds: 10));
    final existing = _appointments.where((a) =>
        a.patientId == patientId &&
        a.doctorId == doctorId &&
        a.createdAt.isAfter(tenSecondsAgo) &&
        a.status != 'cancelled').firstOrNull;

    if (existing != null) {
      debugPrint('OpdProvider: Duplicate appointment prevented for patient $patientName');
      return existing;
    }

    final appt = Appointment(
      patientId: patientId,
      patientName: patientName,
      patientPhone: patientPhone,
      doctorId: doctorId,
      doctorName: doctorName,
      tokenNumber: _nextTokenForToday(),
      consultationFee: consultationFee,
      paymentMethod: paymentMethod,
      scheduledAt: scheduledAt ?? robustNow,
      isWalkIn: isWalkIn,
    );
    ObjectBoxService.instance.appointmentBox.put(appt);

    // Log appointment creation
    AuditService.instance.log(
      action: 'CREATE',
      entityType: 'Appointment',
      entityId: appt.id.toString(),
      description: 'Created Appointment for patient ${appt.patientName} with doctor ${appt.doctorName} (Token: #${appt.tokenNumber})',
      details: {
        'appointmentId': appt.id,
        'patientName': appt.patientName,
        'doctorName': appt.doctorName,
        'tokenNumber': appt.tokenNumber,
        'consultationFee': appt.consultationFee,
        'paymentMethod': appt.paymentMethod,
        'isWalkIn': appt.isWalkIn,
      },
      actor: actor,
    );

    // Generate and save separate consultation fee advance transaction
    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;

    if (consultationFee > 0) {
      final dateStr = '${robustNow.year}${robustNow.month.toString().padLeft(2, '0')}${robustNow.day.toString().padLeft(2, '0')}';
      final timeStr = '${robustNow.hour.toString().padLeft(2, '0')}${robustNow.minute.toString().padLeft(2, '0')}${robustNow.second.toString().padLeft(2, '0')}';
      final msStr = robustNow.millisecond.toString().padLeft(3, '0');
      final invNo = 'OPD-$dateStr-$timeStr-$msStr';

      final consultationItem = SaleItem(
        medicineId: 0,
        procedureId: 0,
        medicineName: 'Consultation Fee (Dr. $doctorName)',
        qty: 1,
        unitPrice: consultationFee,
        isProcedure: true,
      );

      double fCash = 0, fUpi = 0, fCard = 0;
      if (paymentMethod.toLowerCase() == 'upi') {
        fUpi = consultationFee;
      } else if (paymentMethod.toLowerCase() == 'card') {
        fCard = consultationFee;
      } else {
        fCash = consultationFee;
      }

      String patientUhid = '';
      final patient = ObjectBoxService.instance.patientBox.get(patientId);
      if (patient != null) {
        patientUhid = patient.uhid;
      }

      final advanceSale = Sale(
        invoiceNo: invNo,
        patientId: patientId,
        patientName: patientName,
        patientPhone: patientPhone,
        patientUhid: patientUhid,
        subtotal: consultationFee,
        discount: 0,
        taxRate: 0,
        taxAmount: 0,
        total: consultationFee,
        paymentMethod: paymentMethod,
        cashAmount: fCash,
        upiAmount: fUpi,
        cardAmount: fCard,
        isClinicalDispense: true,
        linkedAppointmentId: appt.id,
        itemsJson: jsonEncode([consultationItem.toJson()]),
        createdAt: robustNow,
      );

      ObjectBoxService.instance.saleBox.put(advanceSale);

      if (isHub) {
        if (LocalServerService.instance.isRunning) {
          LocalServerService.instance.broadcast({'event': 'sales_updated'});
        }
      } else if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'sale',
          action: 'create',
          data: advanceSale.toJson(),
        );
      }
      salesProvider?.load();
    }

    loadAll();

    // Broadcast or Push network sync for appointment
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
        LocalServerService.instance
            .broadcast({'event': 'appointments_updated'});
        
        final today = DateTime.now();
        final activeCount = ObjectBoxService.instance.appointmentBox
            .getAll()
            .where((x) =>
                x.scheduledAt.year == today.year &&
                x.scheduledAt.month == today.month &&
                x.scheduledAt.day == today.day &&
                x.status != 'done' &&
                x.status != 'cancelled')
            .length;

        LocalServerService.instance.broadcast({
          'event': 'new_patient',
          'patientName': appt.patientName,
          'activeQueueCount': activeCount,
        });

        FirebaseSyncService.instance.pushNotification(
          event: 'new_patient',
          data: {
            'patientName': appt.patientName,
            'activeQueueCount': activeCount,
          },
        );
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'appointment',
        action: 'create',
        data: appt.toJson(),
      );
    }

    return appt;
  }

  Future<void> updateStatus(int appointmentId, String newStatus,
      [SyncService? syncService]) async {
    final appt = ObjectBoxService.instance.appointmentBox.get(appointmentId);
    if (appt == null) return;
    appt.status = newStatus;
    if (newStatus == kStatusWithDoctor) {
      appt.calledAt = await TimeService.getRobustTime();
    } else if (newStatus == kStatusPharmacy) {
      appt.pharmacyAt = await TimeService.getRobustTime();
    } else if (newStatus == kStatusDone) {
      appt.completedAt = await TimeService.getRobustTime();
    }
    ObjectBoxService.instance.appointmentBox.put(appt);
    loadAll();

    // Broadcast sync
    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'appointment',
        action: 'update',
        data: appt.toJson(),
      );
    }
  }

  Future<void> cancelAppointment(int appointmentId, [SyncService? syncService, AppUser? actor, SalesProvider? salesProvider]) async {
    final appt = ObjectBoxService.instance.appointmentBox.get(appointmentId);
    if (appt == null) return;
    appt.status = kStatusCancelled;
    ObjectBoxService.instance.appointmentBox.put(appt);

    // Log appointment cancellation
    AuditService.instance.log(
      action: 'CANCEL',
      entityType: 'Appointment',
      entityId: appt.id.toString(),
      description: 'Cancelled Appointment for patient ${appt.patientName} with token #${appt.tokenNumber}',
      details: {
        'appointmentId': appt.id,
        'patientName': appt.patientName,
        'doctorName': appt.doctorName,
        'tokenNumber': appt.tokenNumber,
      },
      actor: actor,
    );

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;

    // Void the linked OPD sale/receipt if it exists
    final linkedSale = ObjectBoxService.instance.saleBox
        .query(Sale_.linkedAppointmentId.equals(appointmentId))
        .build()
        .findFirst();

    if (linkedSale != null) {
      ObjectBoxService.instance.saleBox.remove(linkedSale.id);

      // Log voided sale
      AuditService.instance.log(
        action: 'VOID',
        entityType: 'Sale',
        entityId: linkedSale.invoiceNo,
        description: 'Voided/Deleted Sale (Invoice: ${linkedSale.invoiceNo}) due to cancelled Appointment (Token: #${appt.tokenNumber})',
        details: {
          'invoiceNo': linkedSale.invoiceNo,
          'total': linkedSale.total,
          'isReturn': linkedSale.isReturn,
          'patientName': linkedSale.patientName,
          'appointmentId': appt.id,
        },
        actor: actor,
      );

      if (isHub) {
        if (LocalServerService.instance.isRunning) {
          LocalServerService.instance.broadcast({'event': 'sales_updated'});
        }
      } else if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'sale',
          action: 'delete',
          data: {'invoiceNo': linkedSale.invoiceNo},
        );
      }
      
      salesProvider?.load();
    }

    loadAll();

    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'appointment',
        action: 'update',
        data: appt.toJson(),
      );
    }
  }

  void updateStatusWithPayment(
      int appointmentId, String newStatus, String paymentMethod,
      [SyncService? syncService]) async {
    final appt = ObjectBoxService.instance.appointmentBox.get(appointmentId);
    if (appt == null) return;
    appt.status = newStatus;
    appt.paymentMethod = paymentMethod;
    if (newStatus == kStatusWithDoctor) {
      appt.calledAt = await TimeService.getRobustTime();
    } else if (newStatus == kStatusPharmacy) {
      appt.pharmacyAt = await TimeService.getRobustTime();
    } else if (newStatus == kStatusDone) {
      appt.completedAt = await TimeService.getRobustTime();
    }
    ObjectBoxService.instance.appointmentBox.put(appt);
    loadAll();

    // Broadcast sync
    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'appointment',
        action: 'update',
        data: appt.toJson(),
      );
    }
  }

  // Doctor CRUD
  void saveDoctor(Doctor d, {SyncService? syncService}) {
    ObjectBoxService.instance.doctorBox.put(d);
    loadAll();

    // Broadcast sync
    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'doctor',
        action: 'create',
        data: d.toJson(),
      );
    }
  }

  void deleteDoctor(int id, {SyncService? syncService}) {
    ObjectBoxService.instance.doctorBox.remove(id);
    loadAll();

    // Broadcast sync
    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'doctor',
        action: 'delete',
        data: {'id': id},
      );
    }
  }

  Doctor? getDoctorById(int id) {
    return _doctors.where((d) => d.id == id).firstOrNull;
  }

  Appointment? getAppointmentById(int id) {
    return _appointments.where((a) => a.id == id).firstOrNull;
  }

  List<Appointment> getAppointmentsForPatient(Patient patient) {
    if (patient.id == 0 && patient.name.isEmpty) return [];
    
    return _appointments.where((a) {
      final idMatch = a.patientId == patient.id;
      final nameMatch = a.patientName.trim().toLowerCase() == patient.name.trim().toLowerCase();
      final phoneMatch = patient.phone.isNotEmpty && a.patientPhone.trim() == patient.phone.trim();

      if (idMatch && nameMatch) return true;
      if (nameMatch && (patient.phone.isEmpty || phoneMatch)) return true;
      return false;
    }).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
  }
}
