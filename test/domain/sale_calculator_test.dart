import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/domain/sale_calculator.dart';
import 'package:medipos/shared/providers/cart_provider.dart';
import 'package:medipos/shared/models/medicine.dart';

void main() {
  group('SaleCalculator Tests', () {
    test('calculateSubtotal should return correct sum', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 100,
        storeStock: 100,
        category: 'Analgesics',
      );
      final item1 = CartItem(medicine: med, qty: 3); // 30.0
      final item2 = CartItem(medicine: med, qty: 2); // 20.0

      final subtotal = SaleCalculator.calculateSubtotal([item1, item2]);
      expect(subtotal, equals(50.0));
    });

    test('calculate should apply discounts and tax rates correctly', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 100,
        storeStock: 100,
        category: 'Analgesics',
      );
      final item = CartItem(medicine: med, qty: 10); // 100.0

      final totals = SaleCalculator.calculate(
        items: [item],
        discountAmount: 10.0,
        storeTaxRate: 18.0,
        isClinicalDispense: false,
        isCompositionScheme: false,
      );

      expect(totals.subtotal, equals(100.0));
      expect(totals.discount, equals(10.0));
      expect(totals.taxRate, equals(0.18));
      expect(totals.taxAmount, equals(16.2)); // (100 - 10) * 0.18
      expect(totals.total, equals(106.2)); // 90 + 16.2
    });
  });
}
