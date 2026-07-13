import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/patient.dart';
import '../models/patient_image.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/audit_service.dart';

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
    // Add a small random suffix to prevent collisions between Android and Hub
    final random = (DateTime.now().microsecondsSinceEpoch % 1000).toString().padLeft(3, '0');
    return 'OPD-$dateStr-${count.toString().padLeft(3, '0')}-$random';
  }

  Patient savePatient(Patient p, [SyncService? syncService, AppUser? actor]) {
    final isNew = p.id == 0;
    if (isNew) {
      p.uhid = generateUhid();
    }

    final oldPatient = isNew ? null : ObjectBoxService.instance.patientBox.get(p.id);
    final oldJson = oldPatient != null ? oldPatient.toJson() : <String, dynamic>{};

    ObjectBoxService.instance.patientBox.put(p);

    // Log patient save/update
    AuditService.instance.log(
      action: isNew ? 'CREATE' : 'UPDATE',
      entityType: 'Patient',
      entityId: p.uhid,
      description: isNew 
          ? 'Registered new patient: ${p.name} (UHID: ${p.uhid})' 
          : 'Updated patient details: ${p.name} (UHID: ${p.uhid})',
      details: isNew
          ? p.toJson()
          : {
              'before': oldJson,
              'after': p.toJson(),
            },
      actor: actor,
    );

    load();

    // Broadcast or Push network sync
    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'patient',
        action: 'create',
        data: p.toJson(),
      );
    }

    return p;
  }

  void deletePatient(int id, {SyncService? syncService, AppUser? actor}) {
    final patient = ObjectBoxService.instance.patientBox.get(id);
    if (patient == null) return;
    final uhid = patient.uhid;
    final name = patient.name;

    // Clean up images first
    final photos = getPatientPhotos(id);
    for (var photo in photos) {
      deletePatientPhoto(photo);
    }

    // Then delete the patient record
    ObjectBoxService.instance.patientBox.remove(id);

    // Log patient deletion
    AuditService.instance.log(
      action: 'DELETE',
      entityType: 'Patient',
      entityId: uhid,
      description: 'Deleted patient record: $name (UHID: $uhid)',
      details: {'uhid': uhid, 'name': name, 'id': id},
      actor: actor,
    );

    load();

    // Broadcast sync
    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'patient_deleted', 'uhid': uhid});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'patient',
        action: 'delete',
        data: {'uhid': uhid},
      );
    }
  }

  Patient? getById(int id) {
    return _patients.where((p) => p.id == id).firstOrNull;
  }

  Patient? getByUhid(String uhid) {
    if (uhid.isEmpty) return null;
    return _patients.where((p) => p.uhid == uhid).firstOrNull;
  }

  Patient? getByInfo(String name, String phone) {
    if (name.isEmpty) return null;
    // Normalize for comparison
    final n = name.trim().toLowerCase();
    final p = phone.trim();

    return _patients.where((pt) {
      final nameMatch = pt.name.trim().toLowerCase() == n;
      final phoneMatch = p.isNotEmpty && pt.phone.trim() == p;
      return nameMatch && (p.isEmpty || phoneMatch);
    }).firstOrNull;
  }

  List<Patient> findPotentialDuplicates(String name, String phone, {int? excludeId}) {
    final n = name.trim().toLowerCase();
    final p = phone.trim();
    if (n.isEmpty) return [];

    // Split name into lowercase words/tokens (length > 2 to ignore minor parts)
    final nameTokens = n.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();

    return _patients.where((pt) {
      if (excludeId != null && pt.id == excludeId) return false;

      // 1. Exact phone match (strong indicator)
      if (p.isNotEmpty && pt.phone.trim() == p) return true;

      final existingName = pt.name.trim().toLowerCase();

      // 2. Exact name match
      if (existingName == n) return true;

      // 3. Token overlap match (e.g. "Ramesh Bind" & "Ramesh")
      final existingTokens = existingName.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
      if (nameTokens.isNotEmpty && existingTokens.isNotEmpty) {
        final intersection = nameTokens.intersection(existingTokens);
        if (intersection.isNotEmpty) return true;
      }

      // 4. Substring match
      if (n.length > 3 && existingName.length > 3) {
        if (existingName.contains(n) || n.contains(existingName)) return true;
      }

      return false;
    }).toList();
  }

  // --- Photograph Management ---

  List<PatientImage> getPatientPhotos(int patientId) {
    return ObjectBoxService.instance.patientImageBox
        .query(PatientImage_.patientId.equals(patientId))
        .order(PatientImage_.date, flags: Order.descending)
        .build()
        .find();
  }

  List<PatientImage> getPatientPhotosRobust(Patient patient) {
    if (patient.id == 0 && patient.name.isEmpty) return [];

    // Photos are only linked by patientId currently.
    // To be robust, we fetch by ID but we should ideally have a way to verify.
    // For now, we fetch by ID but we can also search for photos that might have been synced with wrong ID?
    // But PatientImage doesn't have patientName.
    
    // So for photos, we have to rely on ID or we add patientName to PatientImage.
    // Given the current situation, let's just use the ID but keep the method for future robustness.
    return getPatientPhotos(patient.id);
  }

  Future<void> savePatientPhotos(
    int patientId,
    List<String> sourcePaths, {
    String category = 'General',
    SyncService? syncService,
  }) async {
    if (sourcePaths.isEmpty) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${appDocDir.path}/patient_photos/$patientId');
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }

      for (var sourcePath in sourcePaths) {
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

        final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
        final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
        if (isHub) {
          if (LocalServerService.instance.isRunning) {
            LocalServerService.instance.broadcast({'event': 'sync_received'});
          }
        } else if (isClient) {
          SyncQueueService.instance.addToQueue(
            entity: 'photo',
            action: 'create',
            data: {'id': pImage.id, 'patientId': patientId},
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving patient photos: $e');
    }
  }

  Future<void> savePatientPhoto(
    int patientId,
    String sourcePath, {
    String category = 'General',
    SyncService? syncService,
  }) async {
    await savePatientPhotos(patientId, [sourcePath], category: category, syncService: syncService);
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

      final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      } else if (isClient && uhid.isNotEmpty) {
        SyncQueueService.instance.addToQueue(
          entity: 'photo',
          action: 'delete',
          data: {'uhid': uhid, 'fileName': fileName},
        );
      }
    } catch (e) {
      debugPrint('Error deleting patient photo: $e');
    }
  }
}
