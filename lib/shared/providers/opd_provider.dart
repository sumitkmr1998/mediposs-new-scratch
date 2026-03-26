import 'package:flutter/material.dart';
import '../models/appointment.dart';
import '../models/doctor.dart';
import '../services/objectbox_service.dart';
import '../services/time_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import 'dart:io';

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
        .where((a) =>
            a.scheduledAt.year == today.year &&
            a.scheduledAt.month == today.month &&
            a.scheduledAt.day == today.day &&
            a.status != kStatusCancelled)
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
  }) async {
    final robustNow = await TimeService.getRobustTime();
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
    loadAll();

    // Broadcast or Push network sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
        LocalServerService.instance
            .broadcast({'event': 'appointments_updated'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      // Push to Hub; Hub returns the Hub-assigned ID
      final success = await syncService.pushAppointment(appt);
      if (success) {
        // Re-pull local appointment by Hub ID so updateStatus uses correct ID
        await syncService.pullAppointments();
        loadAll();
      }
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
    }
    ObjectBoxService.instance.appointmentBox.put(appt);
    loadAll();

    // Broadcast sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      // Push status update to Hub
      final success = await syncService.pushAppointment(appt);
      if (!success) {
        debugPrint('OpdProvider: updateStatus push failed for appt ${appt.id}');
      }
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
    }
    ObjectBoxService.instance.appointmentBox.put(appt);
    loadAll();

    // Broadcast sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      final success = await syncService.pushAppointment(appt);
      if (!success) {
        debugPrint(
            'OpdProvider: updateStatusWithPayment push failed for appt ${appt.id}');
      }
    }
  }

  // Doctor CRUD
  void saveDoctor(Doctor d, {SyncService? syncService}) {
    ObjectBoxService.instance.doctorBox.put(d);
    loadAll();

    // Broadcast sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushDoctor(d);
    }
  }

  void deleteDoctor(int id, {SyncService? syncService}) {
    ObjectBoxService.instance.doctorBox.remove(id);
    loadAll();

    // Broadcast sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushDoctorDelete(id);
    }
  }

  Doctor? getDoctorById(int id) {
    return _doctors.where((d) => d.id == id).firstOrNull;
  }

  Appointment? getAppointmentById(int id) {
    return _appointments.where((a) => a.id == id).firstOrNull;
  }

  List<Appointment> getAppointmentsForPatient(int patientId) {
    return _appointments.where((a) => a.patientId == patientId).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
  }
}
