import 'dart:convert';
import '../../../objectbox.g.dart';
import '../../domain/stock_rules.dart';
import '../../models/medicine.dart';
import '../../models/sale.dart';

/// Sale history and inventory are one durable commit on every transport.
class SaleCommit {
  static Sale apply(Store store, Sale incoming) {
    if (incoming.invoiceNo.trim().isEmpty) {
      throw const FormatException('Invoice number is required');
    }
    return store.runInTransaction(TxMode.write, () {
      final sales = store.box<Sale>();
      final medicines = store.box<Medicine>();
      final batches = store.box<MedicineBatch>();
      final query =
          sales.query(Sale_.invoiceNo.equals(incoming.invoiceNo)).build();
      final Sale? existing;
      try {
        existing = query.findFirst();
      } finally {
        query.close();
      }
      if (existing != null) {
        Map<String, dynamic> payload(Sale sale) => sale.toJson()
          ..remove('id')
          ..remove('updatedAt')
          ..remove('synced');
        if (jsonEncode(payload(existing)) == jsonEncode(payload(incoming))) {
          return existing;
        }
        StockRules.revertInventory(
          oldSale: existing,
          getAllMedicines: medicines.getAll,
          putBatch: (batch) => batches.put(batch),
          putMedicine: (medicine) => medicines.put(medicine),
        );
        incoming.id = existing.id;
      } else {
        incoming.id = 0;
      }
      incoming.updatedAt = DateTime.now();
      incoming.synced = true;

      // Normalize medicineIds in itemsJson to match the local Hub medicine database IDs by name
      try {
        final rawList = jsonDecode(incoming.itemsJson);
        if (rawList is List) {
          final allMeds = medicines.getAll();
          final medNameMap = <String, int>{};
          for (final m in allMeds) {
            final key = m.name.trim().toLowerCase();
            if (key.isNotEmpty && !medNameMap.containsKey(key)) {
              medNameMap[key] = m.id;
            }
          }
          bool modified = false;
          final updated = [];
          for (final rawItem in rawList) {
            if (rawItem is Map) {
              final item = Map<String, dynamic>.from(rawItem);
              if (item['isProcedure'] != true) {
                final name =
                    (item['medicineName'] as String? ?? '').trim().toLowerCase();
                final localId = medNameMap[name];
                if (localId != null && item['medicineId'] != localId) {
                  item['medicineId'] = localId;
                  modified = true;
                }
              }
              updated.add(item);
            } else {
              updated.add(rawItem);
            }
          }
          if (modified) {
            incoming.itemsJson = jsonEncode(updated);
          }
        }
      } catch (_) {}

      StockRules.deductInventory(
        sale: incoming,
        getAllMedicines: medicines.getAll,
        putBatch: (batch) => batches.put(batch),
        putMedicine: (medicine) => medicines.put(medicine),
      );
      sales.put(incoming);
      return incoming;
    });
  }

  static void delete(Store store, String invoiceNo) {
    if (invoiceNo.trim().isEmpty) {
      throw const FormatException('Invoice number is required');
    }
    store.runInTransaction(TxMode.write, () {
      final sales = store.box<Sale>();
      final query = sales.query(Sale_.invoiceNo.equals(invoiceNo)).build();
      final Sale? sale;
      try {
        sale = query.findFirst();
      } finally {
        query.close();
      }
      if (sale == null) return;
      StockRules.revertInventory(
        oldSale: sale,
        getAllMedicines: store.box<Medicine>().getAll,
        putBatch: (batch) => store.box<MedicineBatch>().put(batch),
        putMedicine: (medicine) => store.box<Medicine>().put(medicine),
      );
      sales.remove(sale.id);
    });
  }
}
