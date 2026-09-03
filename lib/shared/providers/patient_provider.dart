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
import '../services/mutation_service.dart';
import '../repositories/patient_repository.dart';

class PatientProvider extends ChangeNotifier {
  final PatientRepository _repo = PatientRepository();

  List<Patient> _patients = [];
  String _search = '';

  List<Patient> get patients => _patients;

  /// Already limited by DB query — no full-table filter in Dart.
  List<Patient> get filtered => _patients;

  /// Total count of all registered patients in ObjectBox
  int get totalCount => _repo.count();

  /// Direct database search across all patients (not limited to loaded 100 recent)
  List<Patient> searchPatients(String q, {int limit = 50}) {
    return _repo.search(q, limit: limit);
  }

  void load() {
    if (_search.isEmpty) {
      _patients = _repo.recent(limit: 100);
    } else {
      _patients = _repo.search(_search, limit: 50);
    }
    notifyListeners();
  }

  void setSearch(String q) {
    _search = q;
    // Debounce is UI-side; re-query ObjectBox with limit (not getAll).
    _patients = _repo.search(q, limit: 50);
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

    MutationService.instance.publishEntity(
      entity: 'patient',
      action: isNew ? 'create' : 'update',
      data: p.toJson(),
      hubEvents: const ['patients_updated', 'new_patient'],
    );

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

    MutationService.instance.publish(
      entity: 'patient',
      action: 'delete',
      data: {'uhid': uhid},
      hubEvents: const ['patient_deleted'],
      hubPayload: {'uhid': uhid},
    );
  }

  Patient? getById(int id) {
    if (id <= 0) return null;
    final cached = _patients.where((p) => p.id == id).firstOrNull;
    if (cached != null) return cached;
    return _repo.byId(id);
  }

  Patient? getByUhid(String uhid) {
    if (uhid.isEmpty) return null;
    final cached = _patients.where((p) => p.uhid == uhid).firstOrNull;
    if (cached != null) return cached;
    final q = ObjectBoxService.instance.patientBox
        .query(Patient_.uhid.equals(uhid))
        .build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  Patient? getByInfo(String name, String phone) {
    if (name.isEmpty) return null;
    // Normalize for comparison
    final n = name.trim().toLowerCase();
    final p = phone.trim();

    final cached = _patients.where((pt) {
      final nameMatch = pt.name.trim().toLowerCase() == n;
      final phoneMatch = p.isNotEmpty && pt.phone.trim() == p;
      return nameMatch && (p.isEmpty || phoneMatch);
    }).firstOrNull;
    if (cached != null) return cached;

    // Fallback to database lookup
    final q = ObjectBoxService.instance.patientBox
        .query(Patient_.name.equals(name.trim(), caseSensitive: false))
        .build();
    try {
      final results = q.find();
      if (p.isEmpty) return results.firstOrNull;
      return results.where((pt) => pt.phone.trim() == p).firstOrNull;
    } finally {
      q.close();
    }
  }

  static const Set<String> _commonNames = {
    'kumar', 'singh', 'devi', 'sharma', 'verma', 'yadav', 'gupta', 'khan', 
    'begum', 'kaur', 'prasad', 'patel', 'das', 'bano', 'ali', 'choudhary', 
    'sen', 'roy', 'dutta', 'shah', 'lal', 'ram', 'bai', 'mishra', 'joshi'
  };

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

      // 3. Token overlap match (excluding common names to avoid false positives)
      final existingTokens = existingName.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
      if (nameTokens.isNotEmpty && existingTokens.isNotEmpty) {
        final uniqueNameTokens = nameTokens.difference(_commonNames);
        final uniqueExistingTokens = existingTokens.difference(_commonNames);
        
        if (uniqueNameTokens.isNotEmpty && uniqueExistingTokens.isNotEmpty) {
          // If we have unique tokens, require at least one unique token match
          final uniqueIntersection = uniqueNameTokens.intersection(uniqueExistingTokens);
          if (uniqueIntersection.isNotEmpty) return true;
        } else {
          // Fallback: If one or both names consist ONLY of common names, require at least 2 tokens to match
          final intersection = nameTokens.intersection(existingTokens);
          if (intersection.length >= 2) return true;
        }
      }

      // 4. Substring match (excluding common names to avoid substring matches on generic titles)
      final cleanN = n.split(RegExp(r'\s+')).where((t) => !_commonNames.contains(t)).join(' ');
      final cleanExisting = existingName.split(RegExp(r'\s+')).where((t) => !_commonNames.contains(t)).join(' ');

      if (cleanN.length > 3 && cleanExisting.length > 3) {
        if (cleanExisting.contains(cleanN) || cleanN.contains(cleanExisting)) return true;
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
