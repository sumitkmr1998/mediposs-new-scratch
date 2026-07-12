import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/domain/stock_rules.dart';
import 'package:medipos/shared/models/sale.dart';
import 'package:medipos/shared/models/medicine.dart';

void main() {
  group('StockRules Tests', () {
    test('deductInventory should deduct store stock correctly', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 10,
        storeStock: 10,
        category: 'Analgesics',
      );

      final batch = MedicineBatch(
        id: 1,
        batchNo: 'B1',
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        mainStock: 10,
        storeStock: 10,
      );
      med.batches.add(batch);

      final saleItem = SaleItem(
        medicineId: 1,
        medicineName: 'Paracetamol',
        qty: 3,
        unitPrice: 10.0,
        batchNo: 'B1',
      );

      final sale = Sale(
        invoiceNo: 'INV-100',
        subtotal: 30.0,
        total: 30.0,
        isClinicalDispense: false,
        itemsJson: jsonEncode([saleItem.toJson()]),
      );

      final List<MedicineBatch> savedBatches = [];
      final List<Medicine> savedMedicines = [];

      StockRules.deductInventory(
        sale: sale,
        getAllMedicines: () => [med],
        putBatch: (b) => savedBatches.add(b),
        putMedicine: (m) => savedMedicines.add(m),
      );

      expect(batch.storeStock, equals(7));
      expect(savedBatches.length, equals(1));
      expect(savedMedicines.length, equals(1));
    });

    test('revertInventory should restore store stock correctly', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 7,
        storeStock: 7,
        category: 'Analgesics',
      );

      final batch = MedicineBatch(
        id: 1,
        batchNo: 'B1',
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        mainStock: 7,
        storeStock: 7,
      );
      med.batches.add(batch);

      final saleItem = SaleItem(
        medicineId: 1,
        medicineName: 'Paracetamol',
        qty: 3,
        unitPrice: 10.0,
        batchNo: 'B1',
      );

      final sale = Sale(
        invoiceNo: 'INV-100',
        subtotal: 30.0,
        total: 30.0,
        isClinicalDispense: false,
        itemsJson: jsonEncode([saleItem.toJson()]),
      );

      final List<MedicineBatch> savedBatches = [];
      final List<Medicine> savedMedicines = [];

      StockRules.revertInventory(
        oldSale: sale,
        getAllMedicines: () => [med],
        putBatch: (b) => savedBatches.add(b),
        putMedicine: (m) => savedMedicines.add(m),
      );

      expect(batch.storeStock, equals(10));
      expect(savedBatches.length, equals(1));
      expect(savedMedicines.length, equals(1));
    });
  });
}
