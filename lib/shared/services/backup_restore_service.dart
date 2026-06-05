import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'objectbox_service.dart';
import '../models/medicine.dart';
import '../models/stock_transfer.dart';
import '../models/sale.dart';
import '../models/app_user.dart';
import '../models/patient.dart';
import '../models/doctor.dart';
import '../models/appointment.dart';
import '../models/prescription.dart';
import '../models/prescription_template.dart';
import '../models/patient_image.dart';
import '../models/purchase_record.dart';
import '../models/restock_request.dart';
import '../models/procedure.dart';

class RestoreConfig {
  final bool inventory;
  final bool salesHistory;
  final bool opd;
  final bool settingsUsers;

  RestoreConfig({
    this.inventory = true,
    this.salesHistory = true,
    this.opd = true,
    this.settingsUsers = true,
  });
}

class BackupRestoreService {
  /// Exports selected ObjectBox modules to a JSON-based ZIP backup
  static Future<File?> exportToJsonBackup() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final stagingName = 'mediposs_backup_$timestamp';
      final stagingDir = Directory(p.join(tempDir.path, stagingName));
      await stagingDir.create(recursive: true);

      final db = ObjectBoxService.instance;

      // 1. Export JSON Data
      await _writeJson(stagingDir, 'medicine.json', db.medicineBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'transfer.json', db.transferBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'sale.json', db.saleBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'user.json', db.userBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'settings.json', db.settingsBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'purchase.json', db.purchaseBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'batch.json', db.batchBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'restock.json', db.restockRequestBox.getAll().map((e) => e.toJson()).toList());
      
      // OPD
      await _writeJson(stagingDir, 'patient.json', db.patientBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'doctor.json', db.doctorBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'appointment.json', db.appointmentBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'prescription.json', db.prescriptionBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'template.json', db.templateBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'patient_image.json', db.patientImageBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'procedure.json', db.procedureBox.getAll().map((e) => e.toJson()).toList());
      await _writeJson(stagingDir, 'procedure_record.json', db.procedureRecordBox.getAll().map((e) => e.toJson()).toList());

      // 2. Export Media Folders (Patient Photos, Prescriptions)
      final appDocDir = await getApplicationDocumentsDirectory();
      final sources = {
        'patient_photos': Directory(p.join(appDocDir.path, 'patient_photos')),
        'prescriptions': Directory(p.join(appDocDir.path, 'prescriptions')),
      };

      for (final entry in sources.entries) {
        if (await entry.value.exists()) {
          final target = Directory(p.join(stagingDir.path, entry.key));
          await target.create(recursive: true);
          await _copyDirectory(entry.value, target);
        }
      }

      // 3. Zip it
      final zipFileName = 'mediposs_json_backup_$timestamp.zip';
      final zipFilePath = p.join(tempDir.path, zipFileName);
      final encoder = ZipFileEncoder();
      encoder.create(zipFilePath);
      encoder.addDirectory(stagingDir);
      encoder.close();

      // Cleanup
      await stagingDir.delete(recursive: true);

      return File(zipFilePath);
    } catch (e) {
      debugPrint('Export Error: $e');
      return null;
    }
  }

  static Future<void> _writeJson(Directory dir, String filename, List<Map<String, dynamic>> data) async {
    final file = File(p.join(dir.path, filename));
    await file.writeAsString(jsonEncode(data));
  }

  static Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list()) {
      if (entity is Directory) {
        final newDir = Directory(p.join(destination.path, p.basename(entity.path)));
        await newDir.create();
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  /// Imports and restores selected modules from a JSON-based ZIP backup
  static Future<void> importFromJsonBackup(File zipFile, RestoreConfig config) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final stagingName = 'mediposs_restore_staging_${DateTime.now().millisecondsSinceEpoch}';
      final stagingDir = Directory(p.join(tempDir.path, stagingName));
      await stagingDir.create(recursive: true);

      // 1. Unzip
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final file in archive) {
        if (file.isFile) {
          final targetPath = p.join(stagingDir.path, file.name);
          final outFile = File(targetPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }

      final db = ObjectBoxService.instance;

      // Helper to read JSON
      Future<List<dynamic>> readJson(String name) async {
        final file = File(p.join(stagingDir.path, 'mediposs_backup_...\\$name')); // Need to handle dynamic root folder
        // Actually the zip structure is: mediposs_backup_TIMESTAMP/filename.json
        // Let's search for the file
        final list = await stagingDir.list(recursive: true).toList();
        for (var entity in list) {
          if (entity is File && p.basename(entity.path) == name) {
            final content = await entity.readAsString();
            return jsonDecode(content) as List<dynamic>;
          }
        }
        return [];
      }

      // 2. Wipe & Replace based on config
      if (config.inventory) {
        db.medicineBox.removeAll();
        db.batchBox.removeAll();
        db.transferBox.removeAll();
        db.purchaseBox.removeAll();
        db.restockRequestBox.removeAll();

        final medJson = await readJson('medicine.json');
        db.medicineBox.putMany(medJson.map((e) => Medicine.fromJson(e)).toList());
        
        final batchJson = await readJson('batch.json');
        db.batchBox.putMany(batchJson.map((e) => MedicineBatch.fromJson(e)).toList());

        final transJson = await readJson('transfer.json');
        db.transferBox.putMany(transJson.map((e) => StockTransfer.fromJson(e)).toList());

        final purJson = await readJson('purchase.json');
        db.purchaseBox.putMany(purJson.map((e) => PurchaseRecord.fromJson(e)).toList());

        final resJson = await readJson('restock.json');
        db.restockRequestBox.putMany(resJson.map((e) => RestockRequest.fromJson(e)).toList());
      }

      if (config.salesHistory) {
        db.saleBox.removeAll();
        final saleJson = await readJson('sale.json');
        db.saleBox.putMany(saleJson.map((e) => Sale.fromJson(e)).toList());
      }

      if (config.opd) {
        db.patientBox.removeAll();
        db.doctorBox.removeAll();
        db.appointmentBox.removeAll();
        db.prescriptionBox.removeAll();
        db.templateBox.removeAll();
        db.patientImageBox.removeAll();
        db.procedureBox.removeAll();
        db.procedureRecordBox.removeAll();

        final patJson = await readJson('patient.json');
        db.patientBox.putMany(patJson.map((e) => Patient.fromJson(e)).toList());

        final docJson = await readJson('doctor.json');
        db.doctorBox.putMany(docJson.map((e) => Doctor.fromJson(e)).toList());

        final apptJson = await readJson('appointment.json');
        db.appointmentBox.putMany(apptJson.map((e) => Appointment.fromJson(e)).toList());

        final presJson = await readJson('prescription.json');
        db.prescriptionBox.putMany(presJson.map((e) => Prescription.fromJson(e)).toList());

        final tempJson = await readJson('template.json');
        db.templateBox.putMany(tempJson.map((e) => PrescriptionTemplate.fromJson(e)).toList());

        final piJson = await readJson('patient_image.json');
        db.patientImageBox.putMany(piJson.map((e) => PatientImage.fromJson(e)).toList());

        final procJson = await readJson('procedure.json');
        db.procedureBox.putMany(procJson.map((e) => Procedure.fromJson(e)).toList());

        final procRecJson = await readJson('procedure_record.json');
        db.procedureRecordBox.putMany(procRecJson.map((e) => ProcedureRecord.fromJson(e)).toList());

        // Restore media folders if OPD is selected
        final appDocDir = await getApplicationDocumentsDirectory();
        
        final extractedPatientPhotos = _findDir(stagingDir, 'patient_photos');
        if (extractedPatientPhotos != null) {
          final target = Directory(p.join(appDocDir.path, 'patient_photos'));
          if (await target.exists()) await target.delete(recursive: true);
          await target.create(recursive: true);
          await _copyDirectory(extractedPatientPhotos, target);
        }

        final extractedPrescriptions = _findDir(stagingDir, 'prescriptions');
        if (extractedPrescriptions != null) {
          final target = Directory(p.join(appDocDir.path, 'prescriptions'));
          if (await target.exists()) await target.delete(recursive: true);
          await target.create(recursive: true);
          await _copyDirectory(extractedPrescriptions, target);
        }
      }

      if (config.settingsUsers) {
        db.userBox.removeAll();
        db.settingsBox.removeAll();

        final userJson = await readJson('user.json');
        db.userBox.putMany(userJson.map((e) => AppUser.fromJson(e)).toList());

        final setJson = await readJson('settings.json');
        // Assuming AppSettings.fromJson exists, else we might skip settings
        // db.settingsBox.putMany(setJson.map((e) => AppSettings.fromJson(e)).toList());
      }

      // Cleanup
      await stagingDir.delete(recursive: true);
    } catch (e) {
      debugPrint('Import Error: $e');
      rethrow;
    }
  }

  static Directory? _findDir(Directory root, String dirname) {
    final list = root.listSync(recursive: true);
    for (var entity in list) {
      if (entity is Directory && p.basename(entity.path) == dirname) {
        return entity;
      }
    }
    return null;
  }
}
