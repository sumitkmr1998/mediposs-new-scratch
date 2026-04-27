import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/patient.dart';
import '../models/patient_image.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';

class PatientProvider extends ChangeNotifier {
  List<Patient> _patients = [];
  String _search = '';

  List<Patient> get patients => _patients;

  List<Patient> get filtered {
    if (_search.isEmpty) return _patients;
    final q = _search.toLowerCase();
    return _patients
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.phone.contains(q) ||
              p.uhid.toLowerCase().contains(q),
        )
        .toList();
  }

  void load() {
    _patients = ObjectBoxService.instance.patientBox.getAll()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  String generateUhid() {
    final now = DateTime.now();
    final dateStr = DateFormat('ddMMyy').format(now);
    final count = ObjectBoxService.instance.patientBox.count() + 1;
    return 'OPD-$dateStr-${count.toString().padLeft(4, '0')}';
  }

  Patient savePatient(Patient p, [SyncService? syncService]) {
    if (p.id == 0) {
      p.uhid = generateUhid();
    }
    ObjectBoxService.instance.patientBox.put(p);
    load();

    // Broadcast or Push network sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushPatient(p);
    }

    return p;
  }

  void deletePatient(int id, {SyncService? syncService}) {
    // Clean up images first
    final photos = getPatientPhotos(id);
    for (var photo in photos) {
      deletePatientPhoto(photo);
    }

    // Then delete the patient record
    ObjectBoxService.instance.patientBox.remove(id);
    load();

    // Broadcast sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushPatientDelete(id);
    }
  }

  Patient? getById(int id) {
    return _patients.where((p) => p.id == id).firstOrNull;
  }

  // --- Photograph Management ---

  List<PatientImage> getPatientPhotos(int patientId) {
    return ObjectBoxService.instance.patientImageBox
        .query(PatientImage_.patientId.equals(patientId))
        .order(PatientImage_.date, flags: Order.descending)
        .build()
        .find();
  }

  Future<void> savePatientPhoto(
    int patientId,
    String sourcePath, {
    String category = 'General',
    SyncService? syncService,
  }) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${appDocDir.path}/patient_photos/$patientId');
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${sourcePath.replaceAll('\\', '/').split('/').last}';
      final savedPath = '${photoDir.path}/$fileName';

      await File(sourcePath).copy(savedPath);

      final pImage = PatientImage(
        patientId: patientId,
        imagePath: savedPath,
        category: category,
        date: DateTime.now(),
      );

      ObjectBoxService.instance.patientImageBox.put(pImage);
      notifyListeners();

      // Sync: on Windows, broadcast so Android Gallery lazy-pulls on next open.
      // On Android, push the photo to Hub using the patient's UHID.
      if (Platform.isWindows) {
        if (LocalServerService.instance.isRunning) {
          LocalServerService.instance.broadcast({'event': 'sync_received'});
        }
      } else if (Platform.isAndroid && syncService != null) {
        // Look up UHID for UHID-based push
        final patient = ObjectBoxService.instance.patientBox.get(patientId);
        final uhid = patient?.uhid ?? '';
        if (uhid.isNotEmpty) {
          syncService.pushPatientPhoto(pImage, uhid);
        }
      }
    } catch (e) {
      debugPrint('Error saving patient photo: $e');
    }
  }

  void deletePatientPhoto(PatientImage pImage, {SyncService? syncService}) {
    try {
      final file = File(pImage.imagePath);
      if (file.existsSync()) {
        file.deleteSync();
      }

      final patient = ObjectBoxService.instance.patientBox.get(pImage.patientId);
      final uhid = patient?.uhid ?? '';
      final fileName = pImage.imagePath.replaceAll('\\', '/').split('/').last;

      ObjectBoxService.instance.patientImageBox.remove(pImage.id);
      notifyListeners();

      if (Platform.isWindows && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      } else if (Platform.isAndroid && syncService != null && uhid.isNotEmpty) {
        syncService.pushPatientPhotoDelete(uhid, fileName);
      }
    } catch (e) {
      debugPrint('Error deleting patient photo: $e');
    }
  }
}
