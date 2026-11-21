import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/models/sale.dart';
import 'package:medipos/shared/utils/consumption_aggregator.dart';

void main() {
  group('ConsumptionAggregator', () {
    test('single pass sums units and revenue by name and id', () {
      final sales = [
        Sale(
          invoiceNo: 'A1',
          subtotal: 100,
          total: 100,
          itemsJson:
              '[{"medicineId":1,"medicineName":"Paracetamol","qty":2,"unitPrice":10,"isProcedure":false}]',
        ),
        Sale(
          invoiceNo: 'A2',
          subtotal: 50,
          total: 50,
          itemsJson:
              '[{"medicineId":1,"medicineName":"Paracetamol","qty":3,"unitPrice":10,"isProcedure":false},'
              '{"medicineId":0,"medicineName":"Consultation Fee - Dr X","qty":1,"unitPrice":200,"isProcedure":true}]',
        ),
      ];

      final r = ConsumptionAggregator.build(sales);
      expect(r.unitsForName('Paracetamol'), 5);
      expect(r.unitsForId(1, fallbackName: 'Paracetamol'), 5);
      expect(r.revenueByName['paracetamol'], 50);
      expect(r.dailyRateForName('Paracetamol', 5), 1.0);
    });

    test('returns reduce quantity (both positive and negative qty in itemsJson)', () {
      final sales = [
        Sale(
          invoiceNo: 'S1',
          subtotal: 40,
          total: 40,
          itemsJson:
              '[{"medicineId":2,"medicineName":"Amox","qty":4,"unitPrice":10,"isProcedure":false}]',
        ),
        Sale(
          invoiceNo: 'R1',
          subtotal: -20,
          total: -20,
          isReturn: true,
          itemsJson:
              '[{"medicineId":2,"medicineName":"Amox","qty":2,"unitPrice":10,"isProcedure":false}]',
        ),
        Sale(
          invoiceNo: 'R2',
          subtotal: -10,
          total: -10,
          isReturn: true,
          // return_dialog and cart_provider write negative qty in itemsJson
          itemsJson:
              '[{"medicineId":2,"medicineName":"Amox","qty":-1,"unitPrice":10,"isProcedure":false}]',
        ),
      ];
      final r = ConsumptionAggregator.build(sales);
      expect(r.unitsForName('Amox'), 1);
    });

    test('protects against cross-device ID collision', () {
      final sales = [
        Sale(
          invoiceNo: 'WIN-1',
          subtotal: 50,
          total: 50,
          itemsJson:
              '[{"medicineId":1,"medicineName":"Paracetamol 500mg","qty":5,"unitPrice":10,"isProcedure":false}]',
        ),
        Sale(
          invoiceNo: 'AND-1',
          subtotal: 500,
          total: 500,
          // Android device happened to use local ObjectBox id 1 for Gloves
          itemsJson:
              '[{"medicineId":1,"medicineName":"Surgical Gloves","qty":100,"unitPrice":5,"isProcedure":false}]',
        ),
      ];
      final r = ConsumptionAggregator.build(sales);
      // Looking up Paracetamol on Windows must NOT return 105
      expect(r.unitsForId(1, fallbackName: 'Paracetamol 500mg'), 5);
      // Looking up Gloves must return 100
      expect(r.unitsForName('Surgical Gloves'), 100);
    });

    test('deduplicates invoices case-insensitively', () {
      final sales = [
        Sale(
          invoiceNo: 'INV-100',
          subtotal: 20,
          total: 20,
          itemsJson:
              '[{"medicineId":3,"medicineName":"Cetirizine","qty":2,"unitPrice":10,"isProcedure":false}]',
        ),
        Sale(
          invoiceNo: 'inv-100',
          subtotal: 20,
          total: 20,
          itemsJson:
              '[{"medicineId":3,"medicineName":"Cetirizine","qty":2,"unitPrice":10,"isProcedure":false}]',
        ),
      ];
      final r = ConsumptionAggregator.build(sales);
      expect(r.unitsForName('Cetirizine'), 2);
    });
  });
}
