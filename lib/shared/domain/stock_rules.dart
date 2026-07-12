import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/sale.dart';
import '../models/medicine.dart';

class StockRules {
  static void revertInventory({
    required Sale oldSale,
    required List<Medicine> Function() getAllMedicines,
    required void Function(MedicineBatch batch) putBatch,
    required void Function(Medicine medicine) putMedicine,
  }) {
    try {
      final list = jsonDecode(oldSale.itemsJson) as List;
      for (final jsonItem in list) {
        final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
        if (item.isProcedure) continue;
        final m = getAllMedicines()
            .where((x) => x.name == item.medicineName)
            .firstOrNull;
        if (m != null) {
          final qty = item.qty.toInt();
          if (qty > 0) {
            final batches = m.batches.toList();
            final batch = batches.where((b) => b.batchNo == item.batchNo).firstOrNull ?? (batches.isNotEmpty ? batches.first : null);
            if (batch != null) {
              if (oldSale.isClinicalDispense) {
                batch.mainStock += qty;
              } else {
                batch.storeStock += qty;
              }
              putBatch(batch);
            }
          } else if (qty < 0) {
            int toDeduct = qty.abs();
            final batches = m.batches.toList();
            final batch = batches.where((b) => b.batchNo == item.batchNo).firstOrNull ?? (batches.isNotEmpty ? batches.first : null);
            if (batch != null) {
              if (oldSale.isClinicalDispense) {
                batch.mainStock = (batch.mainStock - toDeduct).clamp(0, 999999);
              } else {
                batch.storeStock = (batch.storeStock - toDeduct).clamp(0, 999999);
              }
              putBatch(batch);
            }
          }

          m.recalculateStockFromBatches();
          putMedicine(m);
        }
      }
    } catch (e) {
      debugPrint('Hub inventory revert error: $e');
    }
  }

  static void deductInventory({
    required Sale sale,
    required List<Medicine> Function() getAllMedicines,
    required void Function(MedicineBatch batch) putBatch,
    required void Function(Medicine medicine) putMedicine,
  }) {
    try {
      final list = jsonDecode(sale.itemsJson) as List;
      for (final jsonItem in list) {
        final item = SaleItem.fromJson(jsonItem as Map<String, dynamic>);
        if (item.isProcedure) continue;
        final m = getAllMedicines()
            .where((x) => x.name == item.medicineName)
            .firstOrNull;

        if (m != null) {
          final int qty = item.qty.toInt();
          
          if (qty > 0) {
            int remaining = qty;
            final batches = m.batches.toList();
            batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
            for (var b in batches) {
              if (remaining <= 0) break;
              if (b.expiryDate.isBefore(DateTime.now())) continue;
              if (sale.isClinicalDispense) {
                if (b.mainStock > 0) {
                  final d = remaining > b.mainStock ? b.mainStock : remaining;
                  b.mainStock -= d;
                  remaining -= d;
                  putBatch(b);
                }
              } else {
                if (b.storeStock > 0) {
                  final d = remaining > b.storeStock ? b.storeStock : remaining;
                  b.storeStock -= d;
                  remaining -= d;
                  putBatch(b);
                }
              }
            }
          } else if (qty < 0) {
            int toRestore = qty.abs();
            final batches = m.batches.toList();
            if (batches.isNotEmpty) {
              batches.sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
              final latest = batches.first;
              if (sale.isClinicalDispense) {
                latest.mainStock += toRestore;
              } else {
                latest.storeStock += toRestore;
              }
              putBatch(latest);
            }
          }

          m.recalculateStockFromBatches();
          putMedicine(m);
        }
      }
    } catch (e) {
      debugPrint('Hub inventory deduct error: $e');
    }
  }
}
