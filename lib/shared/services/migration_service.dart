import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medicine.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../../objectbox.g.dart';
import 'objectbox_service.dart';
import 'sales_fact_service.dart';

/// One-shot data repairs — never run from provider `load()` paths.
class MigrationService {
  static const _prefsKey = 'mediposs_data_migration_version';
  static const currentVersion = 5;

  /// Run pending migrations after ObjectBox is open.
  static Future<void> runIfNeeded() async {
    if (!ObjectBoxService.isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    final from = prefs.getInt(_prefsKey) ?? 0;
    if (from >= currentVersion) {
      debugPrint('MigrationService: already at v$from');
      return;
    }

    debugPrint('MigrationService: upgrading data v$from → v$currentVersion');

    if (from < 1) {
      final n = _migrateV1DeduplicateBatches();
      debugPrint('MigrationService v1: merged/purged $n duplicate batches');
    }
    if (from < 2) {
      final n = _migrateV2PurgeDuplicateSales();
      debugPrint('MigrationService v2: purged $n duplicate sales by invoiceNo');
    }
    if (from < 3) {
      final n = SalesFactService.instance.backfillFromSales(clearFirst: true);
      debugPrint('MigrationService v3: sales fact backfill processed $n sales');
    }
    if (from < 4) {
      final n = _migrateV4MergeDupPatients();
      debugPrint('MigrationService v4: merged/purged $n duplicate -DUP patients');
    }
    if (from < 5) {
      final purgedSales = _migrateV2PurgeDuplicateSales();
      final backfilled = SalesFactService.instance.backfillFromSales(clearFirst: true);
      debugPrint('MigrationService v5: purged $purgedSales duplicate sales and rebuilt $backfilled sales facts');
    }

    await prefs.setInt(_prefsKey, currentVersion);
    debugPrint('MigrationService: done (v$currentVersion)');
  }

  /// Merge duplicate batch numbers per medicine (same as former InventoryProvider load hook).
  static int _migrateV1DeduplicateBatches() {
    final db = ObjectBoxService.instance;
    final allMeds = db.medicineBox.getAll();
    final batchesToDelete = <MedicineBatch>[];
    final batchesToUpdate = <MedicineBatch>[];
    var changed = 0;

    for (final m in allMeds) {
      if (m.batches.length < 2) continue;

      final uniqueBatches = <String, MedicineBatch>{};
      var medicineChanged = false;

      for (final b in m.batches) {
        final key = b.batchNo.trim().toUpperCase();
        if (key.isEmpty) continue;

        if (!uniqueBatches.containsKey(key)) {
          uniqueBatches[key] = b;
        } else {
          final target = uniqueBatches[key]!;
          target.mainStock += b.mainStock;
          target.storeStock += b.storeStock;
          target.bulkClinicStock += b.bulkClinicStock;
          target.bulkStoreStock += b.bulkStoreStock;
          batchesToUpdate.add(target);
          batchesToDelete.add(b);
          medicineChanged = true;
          changed++;
        }
      }

      if (medicineChanged) {
        m.recalculateStockFromBatches();
        db.medicineBox.put(m);
      }
    }

    if (batchesToUpdate.isNotEmpty) {
      db.batchBox.putMany(batchesToUpdate);
    }
    for (final b in batchesToDelete) {
      b.medicine.target = null;
      db.batchBox.remove(b.id);
    }
    return changed;
  }

  /// Keep highest-id sale per invoiceNo; remove the rest.
  static int _migrateV2PurgeDuplicateSales() {
    final box = ObjectBoxService.instance.saleBox;
    // Stream in chunks to avoid holding everything if possible — full scan once at migrate.
    final all = box.getAll();
    final bestByInvoice = <String, Sale>{};
    final toDelete = <int>[];

    for (final s in all) {
      final inv = s.invoiceNo;
      if (inv.isEmpty) continue;
      final existing = bestByInvoice[inv];
      if (existing == null) {
        bestByInvoice[inv] = s;
      } else if (s.id > existing.id) {
        toDelete.add(existing.id);
        bestByInvoice[inv] = s;
      } else {
        toDelete.add(s.id);
      }
    }

    if (toDelete.isNotEmpty) {
      box.removeMany(toDelete);
    }
    return toDelete.length;
  }

  /// Merges any patients with '-DUP' suffix created by legacy sync into their original record.
  static int _migrateV4MergeDupPatients() {
    final db = ObjectBoxService.instance;
    final allPatients = db.patientBox.getAll();
    final dupPatients = allPatients.where((p) => p.uhid.contains('-DUP')).toList();
    if (dupPatients.isEmpty) return 0;

    int mergedCount = 0;
    for (final dup in dupPatients) {
      final baseUhid = dup.uhid.replaceAll('-DUP', '').trim();
      if (baseUhid.isEmpty) continue;

      final originalQuery = db.patientBox.query(Patient_.uhid.equals(baseUhid)).build();
      Patient? original;
      try {
        original = originalQuery.findFirst();
      } finally {
        originalQuery.close();
      }

      if (original != null && original.id != dup.id) {
        // Apply newer fields from the edited duplicate to original record
        if (dup.updatedAt.isAfter(original.updatedAt)) {
          original.name = dup.name;
          original.phone = dup.phone;
          original.gender = dup.gender;
          original.age = dup.age;
          original.address = dup.address;
          original.bloodGroup = dup.bloodGroup;
          original.updatedAt = dup.updatedAt;
          db.patientBox.put(original);
        }

        // Re-link appointments from dup.id to original.id
        final apptQuery = db.appointmentBox.query(Appointment_.patientId.equals(dup.id)).build();
        final appts = apptQuery.find();
        apptQuery.close();
        for (final a in appts) {
          a.patientId = original.id;
          a.patientName = original.name;
          a.patientPhone = original.phone;
        }
        if (appts.isNotEmpty) db.appointmentBox.putMany(appts);

        // Re-link prescriptions from dup.id to original.id
        final rxQuery = db.prescriptionBox.query(Prescription_.patientId.equals(dup.id)).build();
        final rxList = rxQuery.find();
        rxQuery.close();
        for (final rx in rxList) {
          rx.patientId = original.id;
          rx.patientName = original.name;
        }
        if (rxList.isNotEmpty) db.prescriptionBox.putMany(rxList);

        // Re-link patient photos from dup.id to original.id
        final photoQuery = db.patientImageBox.query(PatientImage_.patientId.equals(dup.id)).build();
        final photos = photoQuery.find();
        photoQuery.close();
        for (final photo in photos) {
          photo.patientId = original.id;
        }
        if (photos.isNotEmpty) db.patientImageBox.putMany(photos);

        // Re-link sales from dup.id to original.id
        final saleQuery = db.saleBox.query(Sale_.patientId.equals(dup.id)).build();
        final sales = saleQuery.find();
        saleQuery.close();
        for (final s in sales) {
          s.patientId = original.id;
          s.patientName = original.name;
          s.patientPhone = original.phone;
        }
        if (sales.isNotEmpty) db.saleBox.putMany(sales);

        // Remove the duplicate record
        db.patientBox.remove(dup.id);
        mergedCount++;
      } else {
        // If there's no original record, just strip -DUP so this patient has a clean UHID
        dup.uhid = baseUhid;
        db.patientBox.put(dup);
        mergedCount++;
      }
    }
    return mergedCount;
  }
}

