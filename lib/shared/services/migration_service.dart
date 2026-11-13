import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medicine.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../models/appointment.dart';
import 'dart:convert';
import '../../objectbox.g.dart';
import 'objectbox_service.dart';
import 'sales_fact_service.dart';

/// One-shot data repairs — never run from provider `load()` paths.
class MigrationService {
  static const _prefsKey = 'mediposs_data_migration_version';
  static const currentVersion = 8;

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
      debugPrint(
          'MigrationService v4: merged/purged $n duplicate -DUP patients');
    }
    if (from < 5) {
      final purgedSales = _migrateV2PurgeDuplicateSales();
      final backfilled =
          SalesFactService.instance.backfillFromSales(clearFirst: true);
      debugPrint(
          'MigrationService v5: purged $purgedSales duplicate sales and rebuilt $backfilled sales facts');
    }
    if (from < 6) {
      final n = deduplicateBatchesAndHealStock();
      debugPrint(
          'MigrationService v6: healed $n medicines with duplicate batches');
    }
    if (from < 7) {
      final n = _migrateV7HealDuplicateOpdDispenseSales();
      debugPrint(
          'MigrationService v7: healed $n duplicate OPD/Dispense sales records');
    }
    if (from < 8) {
      final n = _migrateV8MergeOpdIntoDispenseTreatmentPackage();
      debugPrint(
          'MigrationService v8: healed and merged $n OPD/Dispense treatment packages');
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
    final dupPatients =
        allPatients.where((p) => p.uhid.contains('-DUP')).toList();
    if (dupPatients.isEmpty) return 0;

    int mergedCount = 0;
    for (final dup in dupPatients) {
      final baseUhid = dup.uhid.replaceAll('-DUP', '').trim();
      if (baseUhid.isEmpty) continue;

      final originalQuery =
          db.patientBox.query(Patient_.uhid.equals(baseUhid)).build();
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
        final apptQuery = db.appointmentBox
            .query(Appointment_.patientId.equals(dup.id))
            .build();
        final appts = apptQuery.find();
        apptQuery.close();
        for (final a in appts) {
          a.patientId = original.id;
          a.patientName = original.name;
          a.patientPhone = original.phone;
        }
        if (appts.isNotEmpty) db.appointmentBox.putMany(appts);

        // Re-link prescriptions from dup.id to original.id
        final rxQuery = db.prescriptionBox
            .query(Prescription_.patientId.equals(dup.id))
            .build();
        final rxList = rxQuery.find();
        rxQuery.close();
        for (final rx in rxList) {
          rx.patientId = original.id;
          rx.patientName = original.name;
        }
        if (rxList.isNotEmpty) db.prescriptionBox.putMany(rxList);

        // Re-link patient photos from dup.id to original.id
        final photoQuery = db.patientImageBox
            .query(PatientImage_.patientId.equals(dup.id))
            .build();
        final photos = photoQuery.find();
        photoQuery.close();
        for (final photo in photos) {
          photo.patientId = original.id;
        }
        if (photos.isNotEmpty) db.patientImageBox.putMany(photos);

        // Re-link sales from dup.id to original.id
        final saleQuery =
            db.saleBox.query(Sale_.patientId.equals(dup.id)).build();
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

  /// Merges and purges duplicate batches per medicine.
  /// If duplicate batches with the same batch number were created (e.g. by cloud sync),
  /// keeps the primary batch with accurate quantities, purges redundant batch records,
  /// refreshes the medicine's ToMany relations, and recalculates stock.
  static int deduplicateBatchesAndHealStock() {
    if (!ObjectBoxService.isInitialized) return 0;
    final db = ObjectBoxService.instance;
    final allMeds = db.medicineBox.getAll();
    int healedCount = 0;

    for (final m in allMeds) {
      final allDbBatches = db.batchBox
          .query(MedicineBatch_.medicine.equals(m.id))
          .build()
          .find();
      if (allDbBatches.length < 2) continue;

      final batchMap = <String, MedicineBatch>{};
      final dupBatchIdsToRemove = <int>[];

      for (final b in allDbBatches) {
        final key = b.batchNo.trim().toUpperCase();
        if (key.isEmpty) continue;
        if (!batchMap.containsKey(key)) {
          batchMap[key] = b;
        } else {
          final primary = batchMap[key]!;
          // If primary has 0 stock at some location while duplicate has non-zero, preserve it
          if (primary.mainStock == 0 && b.mainStock > 0)
            primary.mainStock = b.mainStock;
          if (primary.storeStock == 0 && b.storeStock > 0)
            primary.storeStock = b.storeStock;
          if (primary.bulkClinicStock == 0 && b.bulkClinicStock > 0)
            primary.bulkClinicStock = b.bulkClinicStock;
          if (primary.bulkStoreStock == 0 && b.bulkStoreStock > 0)
            primary.bulkStoreStock = b.bulkStoreStock;
          if (primary.sellingPrice <= 0 && b.sellingPrice > 0)
            primary.sellingPrice = b.sellingPrice;
          if (primary.purchasePrice <= 0 && b.purchasePrice > 0)
            primary.purchasePrice = b.purchasePrice;
          dupBatchIdsToRemove.add(b.id);
        }
      }

      if (dupBatchIdsToRemove.isNotEmpty) {
        db.batchBox.putMany(batchMap.values.toList());
        for (final id in dupBatchIdsToRemove) {
          db.batchBox.remove(id);
        }
        m.batches.clear();
        final refreshed = db.batchBox
            .query(MedicineBatch_.medicine.equals(m.id))
            .build()
            .find();
        m.batches.addAll(refreshed);
        m.recalculateStockFromBatches();
        db.medicineBox.put(m);
        healedCount++;
      }
    }

    return healedCount;
  }

  /// Heals legacy DISP- sales that erroneously included consultation fees when an OPD sale
  /// already existed, removes duplicate consultation fee line items, and restores accurate totals.
  static int _migrateV7HealDuplicateOpdDispenseSales() {
    final db = ObjectBoxService.instance;
    final saleBox = db.saleBox;
    final apptBox = db.appointmentBox;
    final allSales = saleBox.getAll();
    var healedCount = 0;

    // 1. Mark all appointments that have an OPD sale as consultationBilled = true
    final opdSales = allSales.where((s) => s.invoiceNo.startsWith('OPD-')).toList();
    for (final opd in opdSales) {
      if (opd.linkedAppointmentId > 0) {
        final appt = apptBox.get(opd.linkedAppointmentId);
        if (appt != null && !appt.consultationBilled) {
          appt.consultationBilled = true;
          apptBox.put(appt);
        }
      }
    }

    // 2. Identify DISP- sales that duplicate consultation fees
    for (final sale in allSales) {
      if (!sale.invoiceNo.startsWith('DISP-')) continue;
      if (sale.itemsJson.isEmpty || sale.itemsJson == '[]') continue;

      List<SaleItem> items;
      try {
        final dynamic decoded = jsonDecode(sale.itemsJson);
        final list = decoded is List ? decoded : [];
        items = list
            .map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        continue;
      }

      final consultationIndex = items.indexWhere((item) =>
          item.isProcedure && item.medicineName.toLowerCase().startsWith('consultation fee'));

      if (consultationIndex == -1) continue;

      // Check if an OPD sale exists for this dispense sale
      Sale? matchingOpd;
      if (sale.linkedAppointmentId > 0) {
        matchingOpd = opdSales.where((o) => o.linkedAppointmentId == sale.linkedAppointmentId).firstOrNull;
      }
      if (matchingOpd == null && sale.opdInvoiceNo.isNotEmpty) {
        matchingOpd = opdSales.where((o) => o.invoiceNo == sale.opdInvoiceNo).firstOrNull;
      }
      if (matchingOpd == null) {
        final dt = sale.createdAt;
        matchingOpd = opdSales.where((o) {
          final isSameDay = o.createdAt.year == dt.year &&
              o.createdAt.month == dt.month &&
              o.createdAt.day == dt.day;
          if (!isSameDay) return false;
          if (sale.patientId > 0 && o.patientId == sale.patientId) return true;
          if (sale.patientPhone.isNotEmpty && o.patientPhone == sale.patientPhone) return true;
          if (sale.patientName.isNotEmpty &&
              o.patientName.toLowerCase().trim() == sale.patientName.toLowerCase().trim()) return true;
          return false;
        }).firstOrNull;
      }

      // If a matching OPD sale exists, the consultation fee was duplicated!
      if (matchingOpd != null) {
        final consItem = items[consultationIndex];
        final feeDeduction = consItem.lineTotal;

        items.removeAt(consultationIndex);
        sale.itemsJson = jsonEncode(items.map((i) => i.toJson()).toList());
        sale.subtotal = (sale.subtotal - feeDeduction).clamp(0.0, double.infinity);
        sale.total = (sale.total - feeDeduction).clamp(0.0, double.infinity);

        // Adjust payment breakdown
        if (sale.paymentMethod == 'mixed') {
          if (sale.cashAmount >= feeDeduction) {
            sale.cashAmount -= feeDeduction;
          } else if (sale.upiAmount >= feeDeduction) {
            sale.upiAmount -= feeDeduction;
          } else if (sale.cardAmount >= feeDeduction) {
            sale.cardAmount -= feeDeduction;
          } else {
            sale.cashAmount = (sale.cashAmount - feeDeduction).clamp(0.0, double.infinity);
          }
        } else if (sale.paymentMethod == 'cash') {
          sale.cashAmount = sale.total;
        } else if (sale.paymentMethod == 'upi') {
          sale.upiAmount = sale.total;
        } else if (sale.paymentMethod == 'card') {
          sale.cardAmount = sale.total;
        }

        if (sale.opdInvoiceNo.isEmpty) {
          sale.opdInvoiceNo = matchingOpd.invoiceNo;
        }

        saleBox.put(sale);
        healedCount++;
      }
    }

    if (healedCount > 0) {
      SalesFactService.instance.backfillFromSales(clearFirst: true);
    }
    return healedCount;
  }

  /// Merges prior OPD advance receipts into DISP- sales as a single unified treatment package,
  /// ensuring DISP- contains both consultation fee and medicines, merging payment amounts,
  /// and removing the redundant standalone OPD sales to eliminate duplicate sales.
  static int _migrateV8MergeOpdIntoDispenseTreatmentPackage() {
    final db = ObjectBoxService.instance;
    final saleBox = db.saleBox;
    final apptBox = db.appointmentBox;
    final allSales = saleBox.getAll();
    var healedCount = 0;

    final opdSales = allSales.where((s) => s.invoiceNo.startsWith('OPD-')).toList();
    if (opdSales.isEmpty) return 0;

    for (final sale in allSales) {
      if (!sale.invoiceNo.startsWith('DISP-')) continue;

      List<SaleItem> items = [];
      try {
        if (sale.itemsJson.isNotEmpty && sale.itemsJson != '[]') {
          final dynamic decoded = jsonDecode(sale.itemsJson);
          final list = decoded is List ? decoded : [];
          items = list
              .map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      } catch (_) {}

      // Find matching OPD sale
      Sale? matchingOpd;
      if (sale.opdInvoiceNo.isNotEmpty) {
        matchingOpd = opdSales.where((o) => o.invoiceNo.trim() == sale.opdInvoiceNo.trim()).firstOrNull;
      }
      if (matchingOpd == null && sale.linkedAppointmentId > 0) {
        matchingOpd = opdSales.where((o) => o.linkedAppointmentId == sale.linkedAppointmentId).firstOrNull;
      }
      if (matchingOpd == null) {
        final dt = sale.createdAt;
        matchingOpd = opdSales.where((o) {
          final isSameDay = o.createdAt.year == dt.year &&
              o.createdAt.month == dt.month &&
              o.createdAt.day == dt.day;
          if (!isSameDay) return false;
          if (sale.patientId > 0 && o.patientId == sale.patientId) return true;
          if (sale.patientPhone.isNotEmpty && o.patientPhone == sale.patientPhone) return true;
          if (sale.patientName.isNotEmpty &&
              o.patientName.toLowerCase().trim() == sale.patientName.toLowerCase().trim()) return true;
          return false;
        }).firstOrNull;
      }

      if (matchingOpd != null) {
        final fee = matchingOpd.total > 0 ? matchingOpd.total : matchingOpd.subtotal;
        final hasConsultation = items.any((item) =>
            item.isProcedure && item.medicineName.toLowerCase().startsWith('consultation fee'));

        if (!hasConsultation && fee > 0) {
          // Re-insert consultation fee into dispense package
          items.insert(0, SaleItem(
            medicineId: 0,
            procedureId: 0,
            medicineName: 'Consultation Fee',
            qty: 1,
            unitPrice: fee,
            isProcedure: true,
            batchNo: '',
            expiryDate: '',
          ));
          sale.itemsJson = jsonEncode(items.map((i) => i.toJson()).toList());
          sale.subtotal = (sale.subtotal + fee).clamp(0.0, double.infinity);
          sale.total = (sale.total + fee).clamp(0.0, double.infinity);

          // Merge payment amounts
          final opdCash = matchingOpd.cashAmount > 0 ? matchingOpd.cashAmount : (matchingOpd.paymentMethod == 'cash' ? fee : 0.0);
          final opdUpi = matchingOpd.upiAmount > 0 ? matchingOpd.upiAmount : (matchingOpd.paymentMethod == 'upi' ? fee : 0.0);
          final opdCard = matchingOpd.cardAmount > 0 ? matchingOpd.cardAmount : (matchingOpd.paymentMethod == 'card' ? fee : 0.0);

          sale.cashAmount += opdCash;
          sale.upiAmount += opdUpi;
          sale.cardAmount += opdCard;

          if (sale.cashAmount > 0 && sale.upiAmount == 0 && sale.cardAmount == 0) {
            sale.paymentMethod = 'cash';
          } else if (sale.upiAmount > 0 && sale.cashAmount == 0 && sale.cardAmount == 0) {
            sale.paymentMethod = 'upi';
          } else if (sale.cardAmount > 0 && sale.cashAmount == 0 && sale.upiAmount == 0) {
            sale.paymentMethod = 'card';
          } else {
            sale.paymentMethod = 'mixed';
          }
        }

        if (sale.opdInvoiceNo.isEmpty) {
          sale.opdInvoiceNo = matchingOpd.invoiceNo;
        }

        saleBox.put(sale);

        // Delete the redundant merged OPD sale from database
        saleBox.remove(matchingOpd.id);
        opdSales.removeWhere((o) => o.id == matchingOpd!.id);

        if (matchingOpd.linkedAppointmentId > 0) {
          final appt = apptBox.get(matchingOpd.linkedAppointmentId);
          if (appt != null && !appt.consultationBilled) {
            appt.consultationBilled = true;
            apptBox.put(appt);
          }
        }

        healedCount++;
      }
    }

    if (healedCount > 0) {
      SalesFactService.instance.backfillFromSales(clearFirst: true);
    }
    return healedCount;
  }
}
