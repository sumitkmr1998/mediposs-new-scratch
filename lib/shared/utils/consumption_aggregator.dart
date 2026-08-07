import 'dart:convert';

import '../models/sale.dart';

/// Single-pass aggregation of medicine units/revenue from a sales window.
/// O(sales × items) total — not O(medicines × sales × items).
class ConsumptionResult {
  /// Lowercased trimmed medicine name → units sold (returns reduce qty).
  final Map<String, int> unitsByName;

  /// Lowercased trimmed medicine name → line revenue (returns reduce amount).
  final Map<String, double> revenueByName;

  /// medicineId → units (when line item has medicineId > 0).
  final Map<int, int> unitsById;

  /// medicineId → revenue.
  final Map<int, double> revenueById;

  const ConsumptionResult({
    required this.unitsByName,
    required this.revenueByName,
    required this.unitsById,
    required this.revenueById,
  });

  int unitsForName(String name) =>
      unitsByName[name.toLowerCase().trim()] ?? 0;

  int unitsForId(int id, {String? fallbackName}) {
    if (id > 0 && unitsById.containsKey(id)) return unitsById[id]!;
    if (fallbackName != null) return unitsForName(fallbackName);
    return 0;
  }

  double dailyRateForName(String name, int trendDays) {
    if (trendDays <= 0) return 0;
    return unitsForName(name) / trendDays;
  }

  double dailyRateForMedicine({
    required int medicineId,
    required String medicineName,
    required int trendDays,
  }) {
    if (trendDays <= 0) return 0;
    final units = unitsForId(medicineId, fallbackName: medicineName);
    return units / trendDays;
  }
}

class ConsumptionAggregator {
  /// Build consumption maps in one pass over [sales].
  /// Skips procedure lines. Returns decrease qty/revenue on [Sale.isReturn].
  static ConsumptionResult build(List<Sale> sales) {
    final unitsByName = <String, int>{};
    final revenueByName = <String, double>{};
    final unitsById = <int, int>{};
    final revenueById = <int, double>{};

    for (final sale in sales) {
      final sign = sale.isReturn ? -1 : 1;
      List items;
      try {
        items = jsonDecode(sale.itemsJson) as List;
      } catch (_) {
        continue;
      }
      for (final raw in items) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final isProcedure = map['isProcedure'] == true;
        if (isProcedure) continue;

        final name = (map['medicineName'] as String? ?? '').toLowerCase().trim();
        if (name.isEmpty) continue;

        final qty = (map['qty'] as num?)?.toInt() ?? 0;
        final unitPrice = (map['unitPrice'] as num?)?.toDouble() ?? 0;
        final lineTotal = (map['lineTotal'] as num?)?.toDouble() ?? (qty * unitPrice);
        final medicineId = (map['medicineId'] as num?)?.toInt() ?? 0;

        unitsByName[name] = (unitsByName[name] ?? 0) + sign * qty;
        revenueByName[name] = (revenueByName[name] ?? 0) + sign * lineTotal;

        if (medicineId > 0) {
          unitsById[medicineId] = (unitsById[medicineId] ?? 0) + sign * qty;
          revenueById[medicineId] =
              (revenueById[medicineId] ?? 0) + sign * lineTotal;
        }
      }
    }

    return ConsumptionResult(
      unitsByName: unitsByName,
      revenueByName: revenueByName,
      unitsById: unitsById,
      revenueById: revenueById,
    );
  }
}
