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

    test('returns reduce quantity', () {
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
      ];
      final r = ConsumptionAggregator.build(sales);
      expect(r.unitsForName('Amox'), 2);
    });
  });
}
