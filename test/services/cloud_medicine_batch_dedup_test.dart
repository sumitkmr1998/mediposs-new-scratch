import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/models/medicine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cloud Medicine Batch Deduplication & Stock Healing Tests', () {
    test('Simulated duplicate batches cause doubled aggregate stock before healing', () {
      final m = Medicine(
        id: 1,
        name: 'aaa2',
        barcode: '',
        category: 'General',
        unit: 'Pcs',
      );

      // Suppose a sync bug inserted two identical 'ben' batches
      final b1 = MedicineBatch(
        id: 101,
        batchNo: 'ben',
        expiryDate: DateTime(2027, 11, 6),
        mainStock: 9,
        storeStock: 3,
        bulkClinicStock: 6,
        bulkStoreStock: 20,
      );
      final b2 = MedicineBatch(
        id: 102,
        batchNo: 'ben',
        expiryDate: DateTime(2027, 11, 6),
        mainStock: 9,
        storeStock: 3,
        bulkClinicStock: 6,
        bulkStoreStock: 20,
      );

      m.batches.addAll([b1, b2]);
      m.recalculateStockFromBatches();

      // Before healing: aggregate stock is doubled
      expect(m.batches.length, equals(2));
      expect(m.bulkStoreStock, equals(40)); // 20 + 20
      expect(m.bulkClinicStock, equals(12)); // 6 + 6
      expect(m.storeStock, equals(6));      // 3 + 3
      expect(m.mainStock, equals(18));      // 9 + 9
    });

    test('Batch deduplication merges identical batch records and restores accurate stock', () {
      final m = Medicine(
        id: 1,
        name: 'aaa2',
        barcode: '',
        category: 'General',
        unit: 'Pcs',
      );

      final b1 = MedicineBatch(
        id: 101,
        batchNo: 'ben',
        expiryDate: DateTime(2027, 11, 6),
        mainStock: 9,
        storeStock: 3,
        bulkClinicStock: 6,
        bulkStoreStock: 20,
      );
      final b2 = MedicineBatch(
        id: 102,
        batchNo: 'ben',
        expiryDate: DateTime(2027, 11, 6),
        mainStock: 9,
        storeStock: 3,
        bulkClinicStock: 6,
        bulkStoreStock: 20,
      );

      final allBatches = [b1, b2];

      // Deduplication logic mirroring MigrationService and handleExternalDelta
      final batchMap = <String, MedicineBatch>{};
      final duplicateIds = <int>[];

      for (final b in allBatches) {
        final key = b.batchNo.trim().toUpperCase();
        if (key.isEmpty) continue;
        if (!batchMap.containsKey(key)) {
          batchMap[key] = b;
        } else {
          final primary = batchMap[key]!;
          if (primary.mainStock == 0 && b.mainStock > 0) primary.mainStock = b.mainStock;
          if (primary.storeStock == 0 && b.storeStock > 0) primary.storeStock = b.storeStock;
          if (primary.bulkClinicStock == 0 && b.bulkClinicStock > 0) primary.bulkClinicStock = b.bulkClinicStock;
          if (primary.bulkStoreStock == 0 && b.bulkStoreStock > 0) primary.bulkStoreStock = b.bulkStoreStock;
          if (primary.sellingPrice <= 0 && b.sellingPrice > 0) primary.sellingPrice = b.sellingPrice;
          if (primary.purchasePrice <= 0 && b.purchasePrice > 0) primary.purchasePrice = b.purchasePrice;
          duplicateIds.add(b.id);
        }
      }

      expect(duplicateIds, equals([102]), reason: 'Second duplicate batch ID must be identified for removal');
      expect(batchMap.length, equals(1));

      // After healing
      m.batches.clear();
      m.batches.addAll(batchMap.values);
      m.recalculateStockFromBatches();

      expect(m.batches.length, equals(1));
      expect(m.batches.first.batchNo, equals('ben'));
      expect(m.bulkStoreStock, equals(20)); // Restored
      expect(m.bulkClinicStock, equals(6));  // Restored
      expect(m.storeStock, equals(3));       // Restored
      expect(m.mainStock, equals(9));        // Restored
    });

    test('Incoming cloud update safely updates existing batch in place without adding duplicate', () {
      final existingMedicine = Medicine(
        id: 1,
        name: 'aaa2',
        barcode: '',
      );

      final existingBatch = MedicineBatch(
        id: 101,
        batchNo: 'ben',
        expiryDate: DateTime(2027, 11, 6),
        mainStock: 9,
        storeStock: 3,
        bulkClinicStock: 6,
        bulkStoreStock: 20,
      );
      existingMedicine.batches.add(existingBatch);
      existingMedicine.recalculateStockFromBatches();

      // Cloud payload with updated storeStock from 3 -> 5
      final cloudPayload = {
        'name': 'aaa2',
        'barcode': '',
        'batches': [
          {
            'batchNo': 'ben',
            'expiryDate': '2027-11-06T00:00:00.000',
            'mainStock': 9,
            'storeStock': 5,
            'bulkClinicStock': 6,
            'bulkStoreStock': 20,
            'purchasePrice': 0.0,
            'sellingPrice': 0.0,
          }
        ]
      };

      final incomingBatches = cloudPayload['batches'] as List;
      final existingBatchMap = <String, MedicineBatch>{
        'BEN': existingBatch,
      };

      for (var bItem in incomingBatches) {
        final bNo = (bItem['batchNo'] as String? ?? '').trim().toUpperCase();
        final match = existingBatchMap[bNo];
        if (match != null) {
          match
            ..mainStock = bItem['mainStock']
            ..storeStock = bItem['storeStock']
            ..bulkClinicStock = bItem['bulkClinicStock']
            ..bulkStoreStock = bItem['bulkStoreStock'];
        }
      }

      existingMedicine.recalculateStockFromBatches();

      // Ensure no duplicate was created
      expect(existingMedicine.batches.length, equals(1));
      expect(existingMedicine.batches.first.storeStock, equals(5));
      expect(existingMedicine.storeStock, equals(5));
      expect(existingMedicine.bulkStoreStock, equals(20));
    });
  });
}

