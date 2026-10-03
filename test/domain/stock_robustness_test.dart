import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/domain/stock_rules.dart';
import 'package:medipos/shared/models/medicine.dart';
import 'package:medipos/shared/models/purchase_record.dart';
import 'package:medipos/shared/models/sale.dart';
import 'package:medipos/shared/models/stock_transfer.dart';

void main() {
  group('StockTransfer Robustness & Serialization Tests', () {
    test('StockTransfer generates a valid unique UUID automatically', () {
      final t1 = StockTransfer(
        medicineId: 1,
        medicineName: 'Amoxicillin 500mg',
        qty: 10,
        fromWarehouse: 'clinic',
        toWarehouse: 'store',
      );

      final t2 = StockTransfer(
        medicineId: 1,
        medicineName: 'Amoxicillin 500mg',
        qty: 10,
        fromWarehouse: 'clinic',
        toWarehouse: 'store',
      );

      expect(t1.uuid, isNotEmpty);
      expect(t2.uuid, isNotEmpty);
      expect(t1.uuid, isNot(equals(t2.uuid)));
    });

    test('StockTransfer preserves uuid, batchNo, and quantities across JSON serialization', () {
      final now = DateTime.now();
      final original = StockTransfer(
        uuid: 'test-transfer-uuid-1234',
        medicineId: 42,
        medicineName: 'Paracetamol 500mg',
        qty: 50,
        fromWarehouse: 'store',
        toWarehouse: 'clinic',
        batchNo: 'BATCH-2026-A',
        expiryDate: now,
        note: 'Urgent clinic transfer',
        transferredBy: 'Admin',
        transferredAt: now,
        initialFromQty: 100,
        finalFromQty: 50,
        initialToQty: 20,
        finalToQty: 70,
      );

      final json = original.toJson();
      expect(json['uuid'], equals('test-transfer-uuid-1234'));
      expect(json['batchNo'], equals('BATCH-2026-A'));
      expect(json['initialFromQty'], equals(100));
      expect(json['finalFromQty'], equals(50));
      expect(json['initialToQty'], equals(20));
      expect(json['finalToQty'], equals(70));

      final restored = StockTransfer.fromJson(json);
      expect(restored.uuid, equals(original.uuid));
      expect(restored.batchNo, equals(original.batchNo));
      expect(restored.initialFromQty, equals(100));
      expect(restored.finalFromQty, equals(50));
      expect(restored.initialToQty, equals(20));
      expect(restored.finalToQty, equals(70));
    });
  });

  group('PurchaseRecord Robustness & Serialization Tests', () {
    test('PurchaseRecord generates UUID and preserves batchNo and expiryDate across JSON', () {
      final expiry = DateTime(2027, 6, 30);
      final p1 = PurchaseRecord(
        medicineId: 10,
        medicineName: 'Cefixime 200mg',
        qty: 100,
        purchasePrice: 15.5,
        location: 'store',
        batchNo: 'CEF-99',
        expiryDate: expiry,
        initialQty: 50,
        finalQty: 150,
      );

      expect(p1.uuid, isNotEmpty);
      final json = p1.toJson();
      expect(json['uuid'], equals(p1.uuid));
      expect(json['batchNo'], equals('CEF-99'));
      expect(json['expiryDate'], isNotNull);
      expect(json['initialQty'], equals(50));
      expect(json['finalQty'], equals(150));

      final restored = PurchaseRecord.fromJson(json);
      expect(restored.uuid, equals(p1.uuid));
      expect(restored.batchNo, equals('CEF-99'));
      expect(restored.initialQty, equals(50));
      expect(restored.finalQty, equals(150));
    });
  });

  group('Stock Recalculation & Batch Safety Tests', () {
    test('recalculateStockFromBatches preserves stock when medicine has no batches', () {
      final med = Medicine(
        name: 'Simple Syringe',
        purchasePrice: 10.0,
        sellingPrice: 15.0,
        mainStock: 25,
        storeStock: 100,
        bulkClinicStock: 10,
        bulkStoreStock: 20,
      );

      expect(med.batches.isEmpty, isTrue);
      med.recalculateStockFromBatches();

      // Stock should NOT be wiped to 0
      expect(med.mainStock, equals(25));
      expect(med.storeStock, equals(100));
      expect(med.bulkClinicStock, equals(10));
      expect(med.bulkStoreStock, equals(20));
    });

    test('recalculateStockFromBatches accurately aggregates stock when batches exist', () {
      final med = Medicine(
        name: 'Azithromycin',
        purchasePrice: 50.0,
        sellingPrice: 80.0,
      );
      final b1 = MedicineBatch(
        batchNo: 'B1',
        expiryDate: DateTime(2027, 1, 1),
        mainStock: 10,
        storeStock: 20,
      );
      final b2 = MedicineBatch(
        batchNo: 'B2',
        expiryDate: DateTime(2027, 6, 1),
        mainStock: 15,
        storeStock: 30,
      );
      med.batches.addAll([b1, b2]);

      med.recalculateStockFromBatches();
      expect(med.mainStock, equals(25));
      expect(med.storeStock, equals(50));
    });
  });

  group('StockRules Deduction & Reversion Tests', () {
    test('rejects a sale that exceeds available stock', () {
      final med = Medicine(
        name: 'Limited medicine', purchasePrice: 1, sellingPrice: 3,
        storeStock: 2,
      );
      final sale = Sale(
        invoiceNo: 'INV-LOW', subtotal: 9, total: 9,
        itemsJson: jsonEncode([SaleItem(
          medicineId: med.id, medicineName: med.name,
          qty: 3, unitPrice: 3,
        ).toJson()]),
      );
      expect(() => StockRules.deductInventory(
        sale: sale,
        getAllMedicines: () => [med],
        putBatch: (_) {},
        putMedicine: (_) {},
      ), throwsStateError);
      expect(med.storeStock, 2);
    });

    test('rejects a named expired batch even if another batch has stock', () {
      final med = Medicine(name: 'Batch medicine',
          purchasePrice: 1, sellingPrice: 3);
      med.batches.addAll([
        MedicineBatch(batchNo: 'EXPIRED',
            expiryDate: DateTime(2020), storeStock: 10),
        MedicineBatch(batchNo: 'FRESH',
            expiryDate: DateTime(2030), storeStock: 10),
      ]);
      final sale = Sale(invoiceNo: 'INV-EXP', subtotal: 3, total: 3,
          itemsJson: jsonEncode([SaleItem(medicineId: med.id,
              medicineName: med.name, qty: 1, unitPrice: 3,
              batchNo: 'EXPIRED').toJson()]));
      expect(() => StockRules.deductInventory(
        sale: sale, getAllMedicines: () => [med],
        putBatch: (_) {}, putMedicine: (_) {},
      ), throwsStateError);
    });
    test('deductInventory prioritizes exact batchNo matching over FIFO', () {
      final med = Medicine(
        name: 'Metformin 500mg',
        purchasePrice: 2.0,
        sellingPrice: 5.0,
      );
      final soonExpiringBatch = MedicineBatch(
        batchNo: 'EXP-SOON',
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        storeStock: 50,
      );
      final laterExpiringBatch = MedicineBatch(
        batchNo: 'TARGET-BATCH',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        storeStock: 50,
      );
      med.batches.addAll([soonExpiringBatch, laterExpiringBatch]);

      // Sale explicitly sold from TARGET-BATCH
      final saleItem = SaleItem(
        medicineId: 1,
        medicineName: 'Metformin 500mg',
        qty: 10,
        unitPrice: 5.0,
        batchNo: 'TARGET-BATCH',
      );
      final sale = Sale(
        invoiceNo: 'INV-001',
        subtotal: 50.0,
        total: 50.0,
        itemsJson: jsonEncode([saleItem.toJson()]),
        createdAt: DateTime.now(),
        isClinicalDispense: false,
      );

      StockRules.deductInventory(
        sale: sale,
        getAllMedicines: () => [med],
        putBatch: (b) {},
        putMedicine: (m) {},
      );

      // TARGET-BATCH should have been deducted, leaving EXP-SOON untouched
      expect(laterExpiringBatch.storeStock, equals(40));
      expect(soonExpiringBatch.storeStock, equals(50));
      expect(med.storeStock, equals(90));
    });

    test('deductInventory falls back to FIFO when batchNo is missing or not found', () {
      final med = Medicine(
        name: 'Paracetamol 500mg',
        purchasePrice: 1.0,
        sellingPrice: 3.0,
      );
      final earlyBatch = MedicineBatch(
        batchNo: 'BATCH-EARLY',
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        storeStock: 10,
      );
      final lateBatch = MedicineBatch(
        batchNo: 'BATCH-LATE',
        expiryDate: DateTime.now().add(const Duration(days: 300)),
        storeStock: 20,
      );
      med.batches.addAll([earlyBatch, lateBatch]);

      final saleItem = SaleItem(
        medicineId: 1,
        medicineName: 'Paracetamol 500mg',
        qty: 15,
        unitPrice: 3.0,
        batchNo: 'N/A', // Unspecified batch
      );
      final sale = Sale(
        invoiceNo: 'INV-002',
        subtotal: 45.0,
        total: 45.0,
        itemsJson: jsonEncode([saleItem.toJson()]),
        createdAt: DateTime.now(),
        isClinicalDispense: false,
      );

      StockRules.deductInventory(
        sale: sale,
        getAllMedicines: () => [med],
        putBatch: (b) {},
        putMedicine: (m) {},
      );

      // FIFO should exhaust BATCH-EARLY (10 units) and take 5 from BATCH-LATE
      expect(earlyBatch.storeStock, equals(0));
      expect(lateBatch.storeStock, equals(15));
      expect(med.storeStock, equals(15));
    });

    test('deductInventory directly deducts from medicine stock when batches are empty', () {
      final med = Medicine(
        name: 'Unbatched Bandage',
        purchasePrice: 1.0,
        sellingPrice: 2.0,
        mainStock: 10,
        storeStock: 40,
      );

      final saleItem = SaleItem(
        medicineId: 1,
        medicineName: 'Unbatched Bandage',
        qty: 5,
        unitPrice: 2.0,
      );
      final sale = Sale(
        invoiceNo: 'INV-003',
        subtotal: 10.0,
        total: 10.0,
        itemsJson: jsonEncode([saleItem.toJson()]),
        createdAt: DateTime.now(),
        isClinicalDispense: false,
      );

      StockRules.deductInventory(
        sale: sale,
        getAllMedicines: () => [med],
        putBatch: (b) {},
        putMedicine: (m) {},
      );

      expect(med.storeStock, equals(35));
    });

    test('revertInventory restores stock to exact batch or unbatched medicine', () {
      final med = Medicine(
        name: 'Ibuprofen',
        purchasePrice: 2.0,
        sellingPrice: 4.0,
      );
      final targetBatch = MedicineBatch(
        batchNo: 'IBU-01',
        expiryDate: DateTime(2027, 1, 1),
        storeStock: 15,
      );
      med.batches.add(targetBatch);

      final oldSaleItem = SaleItem(
        medicineId: 1,
        medicineName: 'Ibuprofen',
        qty: 5,
        unitPrice: 4.0,
        batchNo: 'IBU-01',
      );
      final oldSale = Sale(
        invoiceNo: 'INV-REF-01',
        subtotal: 20.0,
        total: 20.0,
        itemsJson: jsonEncode([oldSaleItem.toJson()]),
        createdAt: DateTime.now(),
        isClinicalDispense: false,
      );

      StockRules.revertInventory(
        oldSale: oldSale,
        getAllMedicines: () => [med],
        putBatch: (b) {},
        putMedicine: (m) {},
      );

      expect(targetBatch.storeStock, equals(20));
      expect(med.storeStock, equals(20));
    });
  });
}
