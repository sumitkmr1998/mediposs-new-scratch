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
          final targetBatchNo = item.batchNo.trim().toUpperCase();
          final batches = m.batches.toList();
          final exactMatch = (targetBatchNo.isNotEmpty && targetBatchNo != 'N/A')
              ? batches.where((b) => b.batchNo.trim().toUpperCase() == targetBatchNo).firstOrNull
              : null;
          final batch = exactMatch ?? (batches.isNotEmpty ? batches.first : null);

          if (batch != null) {
            if (qty > 0) {
              if (oldSale.isClinicalDispense) {
                batch.mainStock += qty;
              } else {
                batch.storeStock += qty;
              }
              putBatch(batch);
            } else if (qty < 0) {
              int toDeduct = qty.abs();
              if (oldSale.isClinicalDispense) {
                batch.mainStock = (batch.mainStock - toDeduct).clamp(0, 999999);
              } else {
                batch.storeStock = (batch.storeStock - toDeduct).clamp(0, 999999);
              }
              putBatch(batch);
            }
          } else {
            // Fallback if medicine has no batches
            if (qty > 0) {
              if (oldSale.isClinicalDispense) {
                m.mainStock += qty;
              } else {
                m.storeStock += qty;
              }
            } else if (qty < 0) {
              int toDeduct = qty.abs();
              if (oldSale.isClinicalDispense) {
                m.mainStock = (m.mainStock - toDeduct).clamp(0, 999999);
              } else {
                m.storeStock = (m.storeStock - toDeduct).clamp(0, 999999);
              }
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
            final targetBatchNo = item.batchNo.trim().toUpperCase();

            // 1. If medicine has no batches at all, deduct directly from medicine stock
            if (batches.isEmpty) {
              if (sale.isClinicalDispense) {
                m.mainStock = (m.mainStock - remaining).clamp(0, 999999);
              } else {
                m.storeStock = (m.storeStock - remaining).clamp(0, 999999);
              }
              remaining = 0;
            }

            // 2. Prioritize exact batch matching if specified by the selling terminal
            if (remaining > 0 && targetBatchNo.isNotEmpty && targetBatchNo != 'N/A') {
              final matchedBatch = batches
                  .where((b) => b.batchNo.trim().toUpperCase() == targetBatchNo)
                  .firstOrNull;
              if (matchedBatch != null) {
                final currentStock = sale.isClinicalDispense
                    ? matchedBatch.mainStock
                    : matchedBatch.storeStock;
                if (currentStock > 0) {
                  final d = remaining > currentStock ? currentStock : remaining;
                  if (sale.isClinicalDispense) {
                    matchedBatch.mainStock -= d;
                  } else {
                    matchedBatch.storeStock -= d;
                  }
                  remaining -= d;
                  putBatch(matchedBatch);
                }
              }
            }

            // 3. Fallback to FIFO by soonest expiry for any remaining quantity
            if (remaining > 0) {
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
            } else {
              if (sale.isClinicalDispense) {
                m.mainStock = (m.mainStock + toRestore).clamp(0, 999999);
              } else {
                m.storeStock = (m.storeStock + toRestore).clamp(0, 999999);
              }
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
