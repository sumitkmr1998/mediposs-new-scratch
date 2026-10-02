import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'objectbox_service.dart';
import 'chunked_box_io.dart';
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
import '../models/daily_medicine_sales_fact.dart';
import '../../objectbox.g.dart';

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
  /// Exports selected ObjectBox modules to a JSON-based ZIP backup (full baseline).
  static Future<File?> exportToJsonBackup() async {
    return exportBackupPackage(since: null);
  }

  /// Exports either a full baseline backup (since == null) or an incremental delta update (since != null).
  static Future<File?> exportBackupPackage({DateTime? since}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final isIncremental = since != null;
      final typePrefix = isIncremental ? 'mediposs_delta' : 'mediposs_full';
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final stagingName = '${typePrefix}_$timestamp';
      final stagingDir = Directory(p.join(tempDir.path, stagingName));
      await stagingDir.create(recursive: true);

      final db = ObjectBoxService.instance;

      // Write manifest
      final manifest = {
        'type': isIncremental ? 'incremental' : 'full',
        'version': '3.0.12',
        'timestamp': DateTime.now().toIso8601String(),
        if (since != null) 'since': since.toIso8601String(),
      };
      final manifestFile = File(p.join(stagingDir.path, 'manifest.json'));
      await manifestFile.writeAsString(jsonEncode(manifest));

      // 1. Export JSON Data (chunked with optional incremental filter)
      Future<void> exportBox<T>(
        String name,
        dynamic box,
        Map<String, dynamic> Function(T e) toJson, {
        bool Function(T e)? filter,
      }) =>
          ChunkedBoxIo.exportBoxToJsonFile<T>(
            box: box,
            dir: stagingDir,
            filename: name,
            toJson: toJson,
            filter: filter,
          );

      await exportBox<Medicine>(
        'medicine.json',
        db.medicineBox,
        (e) => e.toJson(),
        filter: since == null ? null : (m) => m.updatedAt.isAfter(since),
      );
      await exportBox<StockTransfer>(
        'transfer.json',
        db.transferBox,
        (e) => e.toJson(),
        filter: since == null ? null : (t) => t.transferredAt.isAfter(since),
      );
      await exportBox<Sale>(
        'sale.json',
        db.saleBox,
        (e) => e.toJson(),
        filter: since == null ? null : (s) => s.updatedAt.isAfter(since) || s.createdAt.isAfter(since),
      );
      await exportBox<AppUser>('user.json', db.userBox, (e) => e.toJson());
      await exportBox<AppSettings>('settings.json', db.settingsBox, (e) => e.toJson());
      await exportBox<PurchaseRecord>(
        'purchase.json',
        db.purchaseBox,
        (e) => e.toJson(),
        filter: since == null ? null : (p) => p.purchasedAt.isAfter(since),
      );
      await exportBox<MedicineBatch>('batch.json', db.batchBox, (e) => e.toJson());
      await exportBox<RestockRequest>(
        'restock.json',
        db.restockRequestBox,
        (e) => e.toJson(),
        filter: since == null ? null : (r) => r.requestedAt.isAfter(since),
      );

      // OPD
      await exportBox<Patient>(
        'patient.json',
        db.patientBox,
        (e) => e.toJson(),
        filter: since == null ? null : (p) => p.updatedAt.isAfter(since) || p.createdAt.isAfter(since),
      );
      await exportBox<Doctor>('doctor.json', db.doctorBox, (e) => e.toJson());
      await exportBox<Appointment>(
        'appointment.json',
        db.appointmentBox,
        (e) => e.toJson(),
        filter: since == null ? null : (a) => a.updatedAt.isAfter(since) || a.scheduledAt.isAfter(since),
      );
      await exportBox<Prescription>(
        'prescription.json',
        db.prescriptionBox,
        (e) => e.toJson(),
        filter: since == null ? null : (p) => p.createdAt.isAfter(since),
      );
      await exportBox<PrescriptionTemplate>('template.json', db.templateBox, (e) => e.toJson());
      await exportBox<PatientImage>(
        'patient_image.json',
        db.patientImageBox,
        (e) => e.toJson(),
        filter: since == null ? null : (pi) => pi.date.isAfter(since),
      );
      await exportBox<Procedure>('procedure.json', db.procedureBox, (e) => e.toJson());
      await exportBox<ProcedureRecord>(
        'procedure_record.json',
        db.procedureRecordBox,
        (e) => e.toJson(),
        filter: since == null ? null : (pr) => pr.createdAt.isAfter(since) || pr.date.isAfter(since),
      );
      await exportBox<DailyMedicineSalesFact>(
        'sales_facts.json',
        db.salesFactBox,
        (e) => e.toJson(),
      );

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
          await _copyDirectory(entry.value, target, modifiedSince: since);
        }
      }

      // 3. Zip it
      final zipFileName = '${typePrefix}_backup_$timestamp.zip';
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

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination, {
    DateTime? modifiedSince,
  }) async {
    await for (final entity in source.list()) {
      if (entity is Directory) {
        final newDir = Directory(p.join(destination.path, p.basename(entity.path)));
        await newDir.create(recursive: true);
        await _copyDirectory(entity, newDir, modifiedSince: modifiedSince);
      } else if (entity is File) {
        if (modifiedSince != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(modifiedSince)) {
            continue; // Skip older media during incremental export
          }
        }
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
        final list = await stagingDir.list(recursive: true).toList();
        for (var entity in list) {
          if (entity is File && p.basename(entity.path) == name) {
            final content = await entity.readAsString();
            return jsonDecode(content) as List<dynamic>;
          }
        }
        return [];
      }

      // Check if this is an incremental delta backup
      bool isIncremental = false;
      final manifestList = await stagingDir.list(recursive: true).toList();
      for (var entity in manifestList) {
        if (entity is File && p.basename(entity.path) == 'manifest.json') {
          try {
            final mContent = await entity.readAsString();
            final mMap = jsonDecode(mContent) as Map<String, dynamic>;
            if (mMap['type'] == 'incremental') {
              isIncremental = true;
            }
          } catch (_) {}
        }
      }

      if (isIncremental) {
        debugPrint('BackupRestoreService: Performing Incremental Replay/Merge...');
        // Incremental: Merge and upsert without wiping existing data
        if (config.inventory) {
          final medJson = await readJson('medicine.json');
          for (final mRaw in medJson) {
            final m = Medicine.fromJson(mRaw);
            final existing = db.medicineBox.query(Medicine_.barcode.equals(m.barcode)).build().findFirst()
                ?? db.medicineBox.query(Medicine_.name.equals(m.name)).build().findFirst();
            m.id = existing?.id ?? 0;
            db.medicineBox.put(m);
          }

          final batchJson = await readJson('batch.json');
          for (final bRaw in batchJson) {
            final b = MedicineBatch.fromJson(bRaw);
            final existing = db.batchBox.query(MedicineBatch_.batchNo.equals(b.batchNo)).build().findFirst();
            b.id = existing?.id ?? 0;
            db.batchBox.put(b);
          }

          final transJson = await readJson('transfer.json');
          db.transferBox.putMany(transJson.map((e) => StockTransfer.fromJson(e)).toList());

          final purJson = await readJson('purchase.json');
          db.purchaseBox.putMany(purJson.map((e) => PurchaseRecord.fromJson(e)).toList());
        }

        if (config.salesHistory) {
          final saleJson = await readJson('sale.json');
          for (final sRaw in saleJson) {
            final s = Sale.fromJson(sRaw);
            final existing = db.saleBox.query(Sale_.invoiceNo.equals(s.invoiceNo)).build().findFirst();
            s.id = existing?.id ?? 0;
            db.saleBox.put(s);
          }
        }

        if (config.opd) {
          final patJson = await readJson('patient.json');
          for (final pRaw in patJson) {
            final p = Patient.fromJson(pRaw);
            final existing = db.patientBox.query(Patient_.uhid.equals(p.uhid)).build().findFirst();
            p.id = existing?.id ?? 0;
            db.patientBox.put(p);
          }

          final apptJson = await readJson('appointment.json');
          for (final aRaw in apptJson) {
            final a = Appointment.fromJson(aRaw);
            final existing = db.appointmentBox.query(
              Appointment_.tokenNumber.equals(a.tokenNumber)
                  .and(Appointment_.patientName.equals(a.patientName))
            ).build().findFirst();
            a.id = existing?.id ?? 0;
            db.appointmentBox.put(a);
          }

          final presJson = await readJson('prescription.json');
          for (final prRaw in presJson) {
            final pr = Prescription.fromJson(prRaw);
            pr.id = 0; // Insert delta prescriptions
            db.prescriptionBox.put(pr);
          }

          final procRecJson = await readJson('procedure_record.json');
          for (final prRaw in procRecJson) {
            final pr = ProcedureRecord.fromJson(prRaw);
            pr.id = 0;
            db.procedureRecordBox.put(pr);
          }

          // Restore media without deleting existing target folders
          final appDocDir = await getApplicationDocumentsDirectory();
          final extractedPatientPhotos = _findDir(stagingDir, 'patient_photos');
          if (extractedPatientPhotos != null) {
            final target = Directory(p.join(appDocDir.path, 'patient_photos'));
            await target.create(recursive: true);
            await _copyDirectory(extractedPatientPhotos, target);
          }

          final extractedPrescriptions = _findDir(stagingDir, 'prescriptions');
          if (extractedPrescriptions != null) {
            final target = Directory(p.join(appDocDir.path, 'prescriptions'));
            await target.create(recursive: true);
            await _copyDirectory(extractedPrescriptions, target);
          }
        }
      } else {
        // Full baseline restore: Wipe & Replace based on config
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
          if (setJson.isNotEmpty) {
            db.settingsBox.putMany(setJson.map((e) => AppSettings.fromJson(e)).toList());
          }
        }
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
