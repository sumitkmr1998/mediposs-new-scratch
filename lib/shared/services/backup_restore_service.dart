import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'objectbox_service.dart';
import 'chunked_box_io.dart';
import 'safe_file_paths.dart';
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
    Directory? stagingDir;
    try {
      final tempDir = await getTemporaryDirectory();
      final stagingName = 'mediposs_restore_staging_${DateTime.now().millisecondsSinceEpoch}';
      stagingDir = Directory(p.join(tempDir.path, stagingName));
      await stagingDir.create(recursive: true);

      // 1. Unzip
      if (await zipFile.length() > 256 * 1024 * 1024) {
        throw const FormatException('Backup exceeds the import size limit');
      }
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.length > 10000) {
        throw const FormatException('Backup contains too many entries');
      }
      var expandedBytes = 0;
      final seenPaths = <String>{};
      for (final file in archive) {
        final targetPath = SafeFilePaths.archiveDestination(stagingDir.path, file.name);
        if (!seenPaths.add(targetPath.toLowerCase())) {
          throw const FormatException('Duplicate backup entry');
        }
        if (file.isFile) {
          expandedBytes += file.size;
          if (expandedBytes > 512 * 1024 * 1024) {
            throw const FormatException('Backup expands beyond the size limit');
          }
          final outFile = File(targetPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }

      final db = ObjectBoxService.instance;

      final manifestList = await stagingDir.list(recursive: true).toList();
      final filesByName = <String, File>{};
      for (final entity in manifestList) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (!name.endsWith('.json')) continue;
          if (filesByName.containsKey(name)) {
            throw FormatException('Duplicate backup module: $name');
          }
          filesByName[name] = entity;
        }
      }
      final manifestFile = filesByName['manifest.json'];
      if (manifestFile == null) {
        throw const FormatException('Backup manifest is missing');
      }
      final manifest = jsonDecode(await manifestFile.readAsString());
      if (manifest is! Map ||
          (manifest['type'] != 'full' && manifest['type'] != 'incremental')) {
        throw const FormatException('Backup manifest is invalid');
      }
      final isIncremental = manifest['type'] == 'incremental';
      final requiredFiles = <String>{
        if (config.inventory) ...{
          'medicine.json', 'batch.json', 'transfer.json',
          'purchase.json', 'restock.json',
        },
        if (config.salesHistory) ...{'sale.json', 'sales_facts.json'},
        if (config.opd) ...{
          'patient.json', 'doctor.json', 'appointment.json',
          'prescription.json', 'template.json', 'patient_image.json',
          'procedure.json', 'procedure_record.json',
        },
        if (config.settingsUsers) ...{'user.json', 'settings.json'},
      };
      final parsedModules = <String, List<dynamic>>{};
      for (final name in requiredFiles) {
        final source = filesByName[name];
        if (source == null) throw FormatException('Backup is missing $name');
        final parsed = jsonDecode(await source.readAsString());
        if (parsed is! List || parsed.any((row) => row is! Map)) {
          throw FormatException('Backup module $name is invalid');
        }
        parsedModules[name] = parsed;
      }
      List<dynamic> readJson(String name) => parsedModules[name]!;

      // Keep a recovery copy if a later media operation or process crash fails.
      final recoverySource = await exportBackupPackage(since: null);
      if (recoverySource == null) {
        throw StateError('Could not create a recovery backup');
      }
      final supportDir = await getApplicationSupportDirectory();
      final recoveryDir = Directory(p.join(supportDir.path, 'restore_recovery'));
      await recoveryDir.create(recursive: true);
      await recoverySource.copy(p.join(recoveryDir.path,
          'before_restore_${DateTime.now().millisecondsSinceEpoch}.zip'));

      db.store.runInTransaction(TxMode.write, () {

      if (isIncremental) {
        debugPrint('BackupRestoreService: Performing Incremental Replay/Merge...');
        // Incremental: Merge and upsert without wiping existing data
        if (config.inventory) {
          final medJson = readJson('medicine.json');
          for (final mRaw in medJson) {
            final m = Medicine.fromJson(mRaw);
            final existing = db.medicineBox.query(Medicine_.barcode.equals(m.barcode)).build().findFirst()
                ?? db.medicineBox.query(Medicine_.name.equals(m.name)).build().findFirst();
            m.id = existing?.id ?? 0;
            db.medicineBox.put(m);
          }

          final batchJson = readJson('batch.json');
          for (final bRaw in batchJson) {
            final b = MedicineBatch.fromJson(bRaw);
            final existing = db.batchBox.query(MedicineBatch_.batchNo.equals(b.batchNo)).build().findFirst();
            b.id = existing?.id ?? 0;
            db.batchBox.put(b);
          }

          final transJson = readJson('transfer.json');
          db.transferBox.putMany(transJson.map((e) => StockTransfer.fromJson(e)).toList());

          final purJson = readJson('purchase.json');
          db.purchaseBox.putMany(purJson.map((e) => PurchaseRecord.fromJson(e)).toList());
        }

        if (config.salesHistory) {
          final saleJson = readJson('sale.json');
          for (final sRaw in saleJson) {
            final s = Sale.fromJson(sRaw);
            final existing = db.saleBox.query(Sale_.invoiceNo.equals(s.invoiceNo)).build().findFirst();
            s.id = existing?.id ?? 0;
            db.saleBox.put(s);
          }
          db.salesFactBox.removeAll();
          db.salesFactBox.putMany(readJson('sales_facts.json')
              .map((e) => DailyMedicineSalesFact.fromJson(e)).toList());
        }

        if (config.opd) {
          final patJson = readJson('patient.json');
          for (final pRaw in patJson) {
            final p = Patient.fromJson(pRaw);
            final existing = db.patientBox.query(Patient_.uhid.equals(p.uhid)).build().findFirst();
            p.id = existing?.id ?? 0;
            db.patientBox.put(p);
          }

          final apptJson = readJson('appointment.json');
          for (final aRaw in apptJson) {
            final a = Appointment.fromJson(aRaw);
            final existing = db.appointmentBox.query(
              Appointment_.tokenNumber.equals(a.tokenNumber)
                  .and(Appointment_.patientName.equals(a.patientName))
            ).build().findFirst();
            a.id = existing?.id ?? 0;
            db.appointmentBox.put(a);
          }

          final presJson = readJson('prescription.json');
          for (final prRaw in presJson) {
            final pr = Prescription.fromJson(prRaw);
            pr.id = 0; // Insert delta prescriptions
            db.prescriptionBox.put(pr);
          }

          final procRecJson = readJson('procedure_record.json');
          for (final prRaw in procRecJson) {
            final pr = ProcedureRecord.fromJson(prRaw);
            pr.id = 0;
            db.procedureRecordBox.put(pr);
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

          final medJson = readJson('medicine.json');
          db.medicineBox.putMany(medJson.map((e) => Medicine.fromJson(e)).toList());
          
          final batchJson = readJson('batch.json');
          db.batchBox.putMany(batchJson.map((e) => MedicineBatch.fromJson(e)).toList());

          final transJson = readJson('transfer.json');
          db.transferBox.putMany(transJson.map((e) => StockTransfer.fromJson(e)).toList());

          final purJson = readJson('purchase.json');
          db.purchaseBox.putMany(purJson.map((e) => PurchaseRecord.fromJson(e)).toList());

          final resJson = readJson('restock.json');
          db.restockRequestBox.putMany(resJson.map((e) => RestockRequest.fromJson(e)).toList());
        }

        if (config.salesHistory) {
          db.saleBox.removeAll();
          final saleJson = readJson('sale.json');
          db.saleBox.putMany(saleJson.map((e) => Sale.fromJson(e)).toList());
          db.salesFactBox.removeAll();
          db.salesFactBox.putMany(readJson('sales_facts.json')
              .map((e) => DailyMedicineSalesFact.fromJson(e)).toList());
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

          final patJson = readJson('patient.json');
          db.patientBox.putMany(patJson.map((e) => Patient.fromJson(e)).toList());

          final docJson = readJson('doctor.json');
          db.doctorBox.putMany(docJson.map((e) => Doctor.fromJson(e)).toList());

          final apptJson = readJson('appointment.json');
          db.appointmentBox.putMany(apptJson.map((e) => Appointment.fromJson(e)).toList());

          final presJson = readJson('prescription.json');
          db.prescriptionBox.putMany(presJson.map((e) => Prescription.fromJson(e)).toList());

          final tempJson = readJson('template.json');
          db.templateBox.putMany(tempJson.map((e) => PrescriptionTemplate.fromJson(e)).toList());

          final piJson = readJson('patient_image.json');
          db.patientImageBox.putMany(piJson.map((e) => PatientImage.fromJson(e)).toList());

          final procJson = readJson('procedure.json');
          db.procedureBox.putMany(procJson.map((e) => Procedure.fromJson(e)).toList());

          final procRecJson = readJson('procedure_record.json');
          db.procedureRecordBox.putMany(procRecJson.map((e) => ProcedureRecord.fromJson(e)).toList());

        }

        if (config.settingsUsers) {
          db.userBox.removeAll();
          db.settingsBox.removeAll();

          final userJson = readJson('user.json');
          db.userBox.putMany(userJson.map((e) => AppUser.fromJson(e)).toList());

          final setJson = readJson('settings.json');
          if (setJson.isNotEmpty) {
            db.settingsBox.putMany(setJson.map((e) =>
                AppSettings.fromJson(e)..autoLoginPin = null).toList());
          }
        }
      }
      });

      if (config.opd) {
        final appDocDir = await getApplicationDocumentsDirectory();
        for (final dirname in ['patient_photos', 'prescriptions']) {
          final source = _findDir(stagingDir, dirname);
          if (source == null) continue;
          final target = Directory(p.join(appDocDir.path, dirname));
          await target.create(recursive: true);
          await _copyDirectory(source, target);
        }
      }
    } catch (e) {
      debugPrint('Import Error: $e');
      rethrow;
    } finally {
      if (stagingDir != null && await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
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
