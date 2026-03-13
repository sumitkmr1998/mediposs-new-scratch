import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/prescription.dart';
import '../models/appointment.dart';
import '../services/objectbox_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';

class PrescriptionProvider extends ChangeNotifier {
  List<Prescription> _prescriptions = [];

  List<Prescription> get prescriptions => _prescriptions;

  // Prescriptions today that are not yet dispensed (for POS bridge)
  List<Prescription> get pendingDispensation => _prescriptions.where((p) {
        final today = DateTime.now();
        return !p.dispensed &&
            p.createdAt.year == today.year &&
            p.createdAt.month == today.month &&
            p.createdAt.day == today.day;
      }).toList();

  void load() {
    _prescriptions = ObjectBoxService.instance.prescriptionBox.getAll()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Prescription savePrescription({
    required int appointmentId,
    required int patientId,
    required String patientName,
    required int doctorId,
    required String doctorName,
    String diagnosis = '',
    String complaints = '',
    String notes = '',
    List<PrescriptionItem> items = const [],
    List<String> labTests = const [],
    Vitals? vitals,
    SyncService? syncService,
  }) {
    // Resolve JSON for items
    final itemsJson = jsonEncode(items.map((i) => i.toJson()).toList());
    final labTestsJson = jsonEncode(labTests);
    final vitalsJson = jsonEncode((vitals ?? const Vitals()).toJson());

    // Check if one already exists for this appointment (update it)
    final existing = _prescriptions
        .where((p) => p.appointmentId == appointmentId)
        .firstOrNull;
    final prescription = existing ??
        Prescription(
          appointmentId: appointmentId,
          patientId: patientId,
          patientName: patientName,
          doctorId: doctorId,
          doctorName: doctorName,
        );

    prescription.diagnosis = diagnosis;
    prescription.complaints = complaints;
    prescription.notes = notes;
    prescription.itemsJson = itemsJson;
    prescription.labTestsJson = labTestsJson;
    prescription.vitalsJson = vitalsJson;

    ObjectBoxService.instance.prescriptionBox.put(prescription);

    // Update appointment status to 'pharmacy' to indicate prescription ready
    final appt = ObjectBoxService.instance.appointmentBox.get(appointmentId);
    if (appt != null && appt.status == kStatusWithDoctor) {
      appt.status = kStatusPharmacy;
      ObjectBoxService.instance.appointmentBox.put(appt);

      if (Platform.isWindows) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    }

    if (Platform.isWindows) {
      LocalServerService.instance.broadcast({'event': 'sync_received'});
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushPrescription(prescription);
      // If we updated appointment status, push that too
      if (appt != null) {
        syncService.pushAppointment(appt);
      }
    }

    load();
    return prescription;
  }

  List<PrescriptionItem> getItems(Prescription p) {
    try {
      final List<dynamic> decoded = jsonDecode(p.itemsJson);
      return decoded.map((j) => PrescriptionItem.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  List<String> getLabTests(Prescription p) {
    try {
      final List<dynamic> decoded = jsonDecode(p.labTestsJson);
      return decoded.cast<String>();
    } catch (_) {
      return [];
    }
  }

  Vitals getVitals(Prescription p) {
    try {
      final Map<String, dynamic> decoded = jsonDecode(p.vitalsJson);
      return Vitals.fromJson(decoded);
    } catch (_) {
      return const Vitals();
    }
  }

  void markDispensed(int prescriptionId, {SyncService? syncService}) {
    final p = ObjectBoxService.instance.prescriptionBox.get(prescriptionId);
    if (p == null) return;
    p.dispensed = true;
    ObjectBoxService.instance.prescriptionBox.put(p);

    if (Platform.isWindows) {
      LocalServerService.instance.broadcast({'event': 'sync_received'});
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushPrescription(p);
    }

    load();
  }

  void deletePrescription(int id, {SyncService? syncService}) {
    ObjectBoxService.instance.prescriptionBox.remove(id);

    if (Platform.isWindows) {
      LocalServerService.instance.broadcast({'event': 'sync_received'});
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushPrescriptionDelete(id);
    }

    load();
  }

  List<Prescription> getPrescriptionsForPatient(int patientId) {
    return _prescriptions.where((p) => p.patientId == patientId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Prescription? getPrescriptionForAppointment(int appointmentId) {
    return _prescriptions
        .where((p) => p.appointmentId == appointmentId)
        .firstOrNull;
  }
}
