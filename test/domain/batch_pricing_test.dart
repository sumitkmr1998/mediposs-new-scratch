import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/models/medicine.dart';
import 'package:medipos/shared/providers/cart_provider.dart';

void main() {
  group('Batch Pricing and Synchronization Tests', () {
    test('recalculateStockFromBatches synchronizes prices from active batch', () {
      final med = Medicine(
        id: 1,
        name: 'Amoxicillin 500mg',
        purchasePrice: 40.0,
        sellingPrice: 50.0,
        mainStock: 10,
        storeStock: 10,
      );

      final batch = MedicineBatch(
        id: 101,
        batchNo: 'BATCH-001',
        expiryDate: DateTime.now().add(const Duration(days: 180)),
        mainStock: 10,
        storeStock: 10,
        purchasePrice: 45.0,
        sellingPrice: 65.0,
      );
      med.batches.add(batch);

      // Recalculate
      med.recalculateStockFromBatches();

      expect(med.sellingPrice, equals(65.0));
      expect(med.purchasePrice, equals(45.0));
      expect(med.mainStock, equals(10));
      expect(med.storeStock, equals(10));
    });

    test('CartItem unitPrice and lineTotal prioritize active batch price', () {
      final med = Medicine(
        id: 2,
        name: 'Cough Syrup',
        purchasePrice: 80.0,
        sellingPrice: 100.0,
        mainStock: 5,
        storeStock: 5,
      );

      final batch = MedicineBatch(
        id: 102,
        batchNo: 'CS-99',
        expiryDate: DateTime.now().add(const Duration(days: 90)),
        mainStock: 5,
        storeStock: 5,
        purchasePrice: 90.0,
        sellingPrice: 130.0,
      );
      med.batches.add(batch);
      med.recalculateStockFromBatches();

      final cartItem = CartItem(medicine: med, qty: 3);

      expect(cartItem.unitPrice, equals(130.0));
      expect(cartItem.lineTotal, equals(390.0));
    });

    test('MedicineBatch and Medicine serialization preserves purchasePrice and sellingPrice', () {
      final med = Medicine(
        id: 3,
        name: 'Azithromycin',
        purchasePrice: 70.0,
        sellingPrice: 95.0,
        mainStock: 20,
        storeStock: 10,
      );

      final batch = MedicineBatch(
        id: 103,
        batchNo: 'AZ-44',
        expiryDate: DateTime(2027, 5, 20),
        mainStock: 20,
        storeStock: 10,
        purchasePrice: 72.5,
        sellingPrice: 110.0,
      );
      med.batches.add(batch);

      final json = med.toJson();
      expect(json['batches'], isNotNull);
      final batchJson = (json['batches'] as List).first as Map<String, dynamic>;
      expect(batchJson['purchasePrice'], equals(72.5));
      expect(batchJson['sellingPrice'], equals(110.0));

      final restored = Medicine.fromJson(json);
      expect(restored.batches.length, equals(1));
      expect(restored.batches.first.purchasePrice, equals(72.5));
      expect(restored.batches.first.sellingPrice, equals(110.0));
    });
  });
}
