import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medicine.dart';
import '../models/sale.dart';
import 'objectbox_service.dart';
import 'sales_fact_service.dart';

/// One-shot data repairs — never run from provider `load()` paths.
class MigrationService {
  static const _prefsKey = 'mediposs_data_migration_version';
  static const currentVersion = 3;

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
}
