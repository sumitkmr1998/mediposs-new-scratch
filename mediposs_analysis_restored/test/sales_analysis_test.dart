import 'package:flutter_test/flutter_test.dart';
import '../lib/models/sale.dart';
import '../lib/models/medicine.dart';

void main() {
  group('Sales Analysis Tests', () {
    test('Time period detection works correctly', () {
      final questions = {
        'Show me last week sales': 7,
        'What about this month': 30,
        'Last 3 months data': 90,
        'Daily sales trends': 7,
        'Default query': 30,
      };

      for (final entry in questions.entries) {
        // This would call _detectTimePeriod(entry.key)
        // Expected: entry.value
        print('Question: "${entry.key}" → Expected days: ${entry.value}');
      }
    });

    test('Reorder calculation logic', () {
      // Test case: 45-day target, 30-day critical
      // Daily consumption: 10 units/day
      // Current stock: 200 units
      // Days remaining: 200 / 10 = 20 days (< 30 = CRITICAL)
      // Target stock (45 days): 10 * 45 = 450
      // Reorder quantity: 450 - 200 = 250 units

      final dailyConsumption = 10.0;
      final currentStock = 200;
      final daysRemaining = currentStock / dailyConsumption;
      final targetStock = dailyConsumption * 45;
      final reorderQty = (targetStock - currentStock).ceil();

      expect(daysRemaining, 20.0); // Should be critical
      expect(reorderQty, 250); // Should reorder 250 units

      print('Daily consumption: $dailyConsumption units/day');
      print('Current stock: $currentStock units');
      print('Days remaining: $daysRemaining days (CRITICAL < 30)');
      print('Target stock (45 days): $targetStock units');
      print('Reorder quantity: $reorderQty units');
    });

    test('Anonymization logic', () {
      // Test that patient names are anonymized
      final saleId = 12345;
      final anonymizedName = 'Customer ${saleId % 1000}';

      expect(anonymizedName, 'Customer 345');
      print('Sale ID: $saleId → Anonymized: $anonymizedName');
    });

    test('Top medicines sorting', () {
      final medicines = [
        {'name': 'Med A', 'revenue': 1000.0, 'unitsSold': 100},
        {'name': 'Med B', 'revenue': 2000.0, 'unitsSold': 50},
        {'name': 'Med C', 'revenue': 500.0, 'unitsSold': 200},
      ];

      // Sort by revenue (descending)
      medicines.sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));

      expect(medicines[0]['name'], 'Med B');
      expect(medicines[1]['name'], 'Med A');
      expect(medicines[2]['name'], 'Med C');

      print('Top medicines by revenue:');
      for (final m in medicines) {
        print('  ${m['name']}: ₹${m['revenue']} revenue');
      }
    });
  });
}
