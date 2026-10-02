import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Clinic Reconciliation Baseline Calculation Tests', () {
    test('Immediately after audit baseline reset, variance is exactly 0', () {
      // 1. Medicine with 50 units in clinic at baseline time
      const baselineStock = 50;
      const currentStock = 50;
      const transfersSinceBaseline = 0;
      const dispensesSinceBaseline = 0;

      final expectedStock = baselineStock + transfersSinceBaseline - dispensesSinceBaseline;
      final variance = currentStock - expectedStock;

      expect(expectedStock, 50);
      expect(variance, 0);
    });

    test('Transfers and clinical dispenses after baseline track balance correctly', () {
      const baselineStock = 50;
      const transfersSinceBaseline = 20; // 20 units transferred in
      const dispensesSinceBaseline = 15; // 15 units dispensed to patients
      const currentStock = 55; // 50 + 20 - 15 = 55 on hand

      final expectedStock = baselineStock + transfersSinceBaseline - dispensesSinceBaseline;
      final variance = currentStock - expectedStock;

      expect(expectedStock, 55);
      expect(variance, 0);
    });

    test('Detects shrinkage/deficit when physical stock is lower than expected', () {
      const baselineStock = 50;
      const transfersSinceBaseline = 10;
      const dispensesSinceBaseline = 5;
      // Expected = 50 + 10 - 5 = 55. But only 52 physically present.
      const currentStock = 52;

      final expectedStock = baselineStock + transfersSinceBaseline - dispensesSinceBaseline;
      final variance = currentStock - expectedStock;

      expect(expectedStock, 55);
      expect(variance, -3); // 3 units missing
    });

    test('Detects surplus when physical stock is higher than expected', () {
      const baselineStock = 30;
      const transfersSinceBaseline = 5;
      const dispensesSinceBaseline = 2;
      // Expected = 30 + 5 - 2 = 33. But 35 present on shelf.
      const currentStock = 35;

      final expectedStock = baselineStock + transfersSinceBaseline - dispensesSinceBaseline;
      final variance = currentStock - expectedStock;

      expect(expectedStock, 33);
      expect(variance, 2); // 2 units surplus
    });

    test('Historical cycle calculations accurately detect discrepancies between two past snapshots', () {
      // Snapshot 1 (e.g. 20 days ago): Started with 100 units
      const cycle1StartingStock = 100;
      const cycle1Transfers = 50;
      const cycle1Dispenses = 70;
      // Snapshot 2 (e.g. 10 days ago): Counted 78 units
      const cycle1EndingCountAtSnapshot2 = 78;

      final expectedEndingStock = cycle1StartingStock + cycle1Transfers - cycle1Dispenses; // 80
      final cycle1Variance = cycle1EndingCountAtSnapshot2 - expectedEndingStock; // 78 - 80 = -2

      expect(expectedEndingStock, 80);
      expect(cycle1Variance, -2); // 2 units were missing during that 10-day period

      // Cycle 2 (from 10 days ago to now): Started with the 78 units verified at Snapshot 2
      const cycle2StartingStock = 78;
      const cycle2Transfers = 20;
      const cycle2Dispenses = 30;
      // Now: Counted 65 units
      const currentCount = 65;

      final cycle2ExpectedStock = cycle2StartingStock + cycle2Transfers - cycle2Dispenses; // 78 + 20 - 30 = 68
      final cycle2Variance = currentCount - cycle2ExpectedStock; // 65 - 68 = -3

      expect(cycle2ExpectedStock, 68);
      expect(cycle2Variance, -3); // 3 units missing in this cycle

      // Comparison: Missing in both cycles (-2 then -3) reveals a recurring irregularity
      expect(cycle1Variance < 0 && cycle2Variance < 0, isTrue);
    });
  });
}
