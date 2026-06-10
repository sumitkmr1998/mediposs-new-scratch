import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p_path;
import '../models/prescription.dart';
import '../models/appointment.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/audit_service.dart';
import '../models/patient_image.dart';
import '../models/patient.dart';
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
    List<String> procedures = const [],
    List<String> images = const [],
    Vitals? vitals,
    SyncService? syncService,
    BuildContext? context,
    AppUser? actor,
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
    final proceduresJson = jsonEncode(procedures);

    // Check if one already exists for this appointment (update it)
    final existing = _prescriptions
        .where((p) => p.appointmentId == appointmentId)
        .firstOrNull;
    final isNew = existing == null;
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
    prescription.proceduresJson = proceduresJson;
    prescription.updatedAt = DateTime.now();

    ObjectBoxService.instance.prescriptionBox.put(prescription);

    // Log prescription save/update
    AuditService.instance.log(
      action: isNew ? 'CREATE' : 'UPDATE',
      entityType: 'Prescription',
      entityId: prescription.id.toString(),
      description: isNew
          ? 'Created Prescription for patient ${prescription.patientName} (Doctor: ${prescription.doctorName})'
          : 'Updated Prescription for patient ${prescription.patientName} (Doctor: ${prescription.doctorName})',
      details: {
        'prescriptionId': prescription.id,
        'appointmentId': prescription.appointmentId,
        'patientId': prescription.patientId,
        'patientName': prescription.patientName,
        'doctorName': prescription.doctorName,
        'diagnosis': prescription.diagnosis,
        'itemsCount': items.length,
      },
      actor: actor,
    );

    // Also add to patient gallery so they are visible in Patient Details
    for (var imagePath in savedImagePaths) {
      final pImage = PatientImage(
        patientId: patientId,
        imagePath: imagePath,
        category: 'Prescription',
        date: DateTime.now(),
      );
      final pImageId = ObjectBoxService.instance.patientImageBox.put(pImage);
      pImage.id = pImageId;

      // Sync to Hub gallery
      if (syncService != null && !syncService.isHub) {
        SyncQueueService.instance.addToQueue(
            entity: 'photo', action: 'create', data: pImage.toJson());
      }
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
    if (appt != null && (appt.status == kStatusWithDoctor || appt.status == kStatusWaiting)) {
      appt.status = kStatusPharmacy;
      ObjectBoxService.instance.appointmentBox.put(appt);
      // Notify OpdProvider to refresh its state
      if (context != null && context.mounted) {
        context.read<OpdProvider>().loadAll();
      }

      final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    }

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;

    if (isHub) {
      LocalServerService.instance.broadcast({'event': 'sync_received'});
    } else if (isClient) {
      final patient = ObjectBoxService.instance.patientBox.get(patientId);
      final syncData = prescription.toJson();
      syncData['patientUhid'] = patient?.uhid ?? '';
      syncData['tokenNumber'] = appt?.tokenNumber ?? 0;

      debugPrint('PrescriptionProvider: Queuing sync for ${prescription.patientName} (UHID: ${patient?.uhid}, Token: ${appt?.tokenNumber})');
      
      SyncQueueService.instance.addToQueue(
        entity: 'prescription',
        action: 'create',
        data: syncData,
      );
      // If we updated appointment status, push that too
      if (appt != null) {
        SyncQueueService.instance.addToQueue(
          entity: 'appointment',
          action: 'update',
          data: appt.toJson(),
        );
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

  List<String> getProcedures(Prescription p) {
    try {
      final List<dynamic> decoded = jsonDecode(p.proceduresJson);
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

  /// Resolves an image path by looking for the filename locally if the absolute path fails.
  /// This is crucial for cross-platform sync (Windows paths on Android).
  Future<String> resolveImagePath(String originalPath) async {
    final file = File(originalPath);
    if (await file.exists()) return originalPath;

    // If not found, try to resolve by filename in local prescription directory
    try {
      final fileName = p_path.basename(originalPath);
      final appDocDir = await getApplicationDocumentsDirectory();
      // Try prescriptions directory first
      final pPath = p_path.join(appDocDir.path, 'prescriptions', 'images', fileName);
      if (await File(pPath).exists()) return pPath;
      
      // Try patient_photos directory (gallery)
      final gPath = p_path.join(appDocDir.path, 'patient_photos');
      if (await Directory(gPath).exists()) {
         // Search recursively in patient_photos
         final entities = await Directory(gPath).list(recursive: true).toList();
         for (final entity in entities) {
           if (entity is File && p_path.basename(entity.path) == fileName) {
             return entity.path;
           }
         }
      }
    } catch (e) {
      debugPrint('Error resolving image path: $e');
    }

    return originalPath; // Fallback to original
  }

  void markDispensed(int prescriptionId, {SyncService? syncService, AppUser? actor}) {
    final p = ObjectBoxService.instance.prescriptionBox.get(prescriptionId);
    if (p == null) return;
    p.dispensed = true;
    ObjectBoxService.instance.prescriptionBox.put(p);

    // Log dispensing
    AuditService.instance.log(
      action: 'UPDATE',
      entityType: 'Prescription',
      entityId: p.id.toString(),
      description: 'Prescription for patient ${p.patientName} marked as dispensed',
      details: {'prescriptionId': p.id, 'patientName': p.patientName, 'dispensed': true},
      actor: actor,
    );

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;

    if (isHub) {
      LocalServerService.instance.broadcast({'event': 'sync_received'});
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'prescription',
        action: 'update',
        data: p.toJson(),
      );
    }

    load();
  }

  void markDispensedByAppointment(int appointmentId,
      {SyncService? syncService, AppUser? actor}) {
    final p = getPrescriptionForAppointment(appointmentId);
    if (p != null) {
      markDispensed(p.id, syncService: syncService, actor: actor);
    }
  }

  void deletePrescription(int id, {SyncService? syncService, AppUser? actor}) {
    final p = ObjectBoxService.instance.prescriptionBox.get(id);
    if (p == null) return;
    final patientName = p.patientName;
    ObjectBoxService.instance.prescriptionBox.remove(id);

    // Log deletion
    AuditService.instance.log(
      action: 'DELETE',
      entityType: 'Prescription',
      entityId: id.toString(),
      description: 'Deleted prescription for patient $patientName',
      details: {'prescriptionId': id, 'patientName': patientName},
      actor: actor,
    );

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;

    if (isHub) {
      LocalServerService.instance.broadcast({'event': 'sync_received'});
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'prescription',
        action: 'delete',
        data: {'id': id},
      );
    }

    load();
  }

  List<Prescription> getPrescriptionsForPatient(Patient patient) {
    if (patient.id == 0 && patient.name.isEmpty) return [];

    return _prescriptions.where((p) {
      final idMatch = p.patientId == patient.id;
      final nameMatch = p.patientName.trim().toLowerCase() == patient.name.trim().toLowerCase();
      final phoneMatch = patient.phone.isNotEmpty && (p.vitalsJson.contains(patient.phone) || nameMatch); // Prescriptions don't have phone in root, but name match is usually enough
      
      // If ID matches, we still check name to avoid collisions
      if (idMatch && nameMatch) return true;
      
      // Fallback to name match for synced data
      if (nameMatch) return true;

      return false;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Prescription? getPrescriptionForAppointment(int appointmentId) {
    return _prescriptions
        .where((p) => p.appointmentId == appointmentId)
        .firstOrNull;
  }
}
