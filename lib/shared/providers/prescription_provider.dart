import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p_path;
import '../models/prescription.dart';
import '../models/appointment.dart';
import '../services/objectbox_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../models/patient_image.dart';
import 'patient_provider.dart';
import 'opd_provider.dart';

class PrescriptionProvider extends ChangeNotifier {
  List<Prescription> _prescriptions = [];

  List<Prescription> get prescriptions => _prescriptions;

  List<Prescription> get pendingDispensation {
    final today = DateTime.now();
    return _prescriptions.where((p) {
      return !p.dispensed &&
          p.createdAt.year == today.year &&
          p.createdAt.month == today.month &&
          p.createdAt.day == today.day;
    }).toList();
  }

  void load() {
    _prescriptions = ObjectBoxService.instance.prescriptionBox.getAll()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> savePrescription({
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
    List<String> images = const [],
    Vitals? vitals,
    SyncService? syncService,
    BuildContext? context,
  }) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final photoDir =
        Directory(p_path.join(appDocDir.path, 'prescriptions', 'images'));
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }

    final List<String> savedImagePaths = [];
    for (var path in images) {
      if (p_path.isWithin(appDocDir.path, path)) {
        savedImagePaths.add(path);
      } else {
        try {
          final fileName =
              'PRES_${DateTime.now().millisecondsSinceEpoch}_${p_path.basename(path)}';
          final savedPath = p_path.join(photoDir.path, fileName);
          await File(path).copy(savedPath);
          savedImagePaths.add(savedPath);
        } catch (e) {
          debugPrint('Error copying prescription image: $e');
          savedImagePaths.add(path);
        }
      }
    }

    // Resolve JSON for items
    final itemsJson = jsonEncode(items.map((i) => i.toJson()).toList());
    final labTestsJson = jsonEncode(labTests);
    final vitalsJson = jsonEncode((vitals ?? const Vitals()).toJson());
    final imagesJson = jsonEncode(savedImagePaths);

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
    prescription.imagesJson = imagesJson;

    ObjectBoxService.instance.prescriptionBox.put(prescription);

    // Also add to patient gallery so they are visible in Patient Details
    for (var imagePath in savedImagePaths) {
      final pImage = PatientImage(
        patientId: patientId,
        imagePath: imagePath,
        category: 'Prescription',
        date: DateTime.now(),
      );
      ObjectBoxService.instance.patientImageBox.put(pImage);
    }

    // Notify PatientProvider to refresh Gallery if context is available
    if (context != null && context.mounted) {
      try {
        context
            .read<PatientProvider>()
            .load(); // refreshes and calls notifyListeners
      } catch (e) {
        debugPrint('Note: PatientProvider not found in current context');
      }
    }

    // Update appointment status to 'pharmacy' to indicate prescription ready
    final appt = ObjectBoxService.instance.appointmentBox.get(appointmentId);
    if (appt != null && appt.status == kStatusWithDoctor) {
      appt.status = kStatusPharmacy;
      ObjectBoxService.instance.appointmentBox.put(appt);
      // Notify OpdProvider to refresh its state
      if (context != null && context.mounted) {
        context.read<OpdProvider>().loadAll();
      }

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

  List<String> getImages(Prescription p) {
    try {
      final List<dynamic> decoded = jsonDecode(p.imagesJson);
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

  void markDispensedByAppointment(int appointmentId,
      {SyncService? syncService}) {
    final p = getPrescriptionForAppointment(appointmentId);
    if (p != null) {
      markDispensed(p.id, syncService: syncService);
    }
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
