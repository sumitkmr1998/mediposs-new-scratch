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
    final nameKey = fallbackName?.toLowerCase().trim();
    final hasName = nameKey != null && nameKey.isNotEmpty;
    final nameUnits = hasName ? (unitsByName[nameKey] ?? 0) : 0;

    // Canonical medicine name is the authoritative identifier across multi-device sync
    // topologies to prevent cross-device integer ID overlap/corruption.
    if (hasName && unitsByName.containsKey(nameKey)) {
      return nameUnits;
    }
    if (id > 0 && unitsById.containsKey(id)) {
      return unitsById[id]!;
    }
    return nameUnits;
  }

  double dailyRateForName(String name, int trendDays) {
    if (trendDays <= 0) return 0;
    final units = unitsForName(name);
    if (units <= 0) return 0.0;
    return units / trendDays;
  }

  double dailyRateForMedicine({
    required int medicineId,
    required String medicineName,
    required int trendDays,
  }) {
    if (trendDays <= 0) return 0;
    final units = unitsForId(medicineId, fallbackName: medicineName);
    if (units <= 0) return 0.0;
    return units / trendDays;
  }
}

class ConsumptionAggregator {
  /// Build consumption maps in one pass over [sales].
  /// Skips procedure lines. Returns decrease qty/revenue on [Sale.isReturn].
  /// Deduplicates sales by invoiceNo (case-insensitive) to prevent duplicate sync counting.
  static ConsumptionResult build(List<Sale> sales) {
    final unitsByName = <String, int>{};
    final revenueByName = <String, double>{};
    final unitsById = <int, int>{};
    final revenueById = <int, double>{};
    final seenInvoices = <String>{};

    for (final sale in sales) {
      final inv = sale.invoiceNo.trim().toUpperCase();
      final saleId = sale.id;
      if (inv.isNotEmpty) {
        if (seenInvoices.contains(inv)) continue;
        seenInvoices.add(inv);
      } else if (saleId > 0) {
        final idKey = '__ID_$saleId';
        if (seenInvoices.contains(idKey)) continue;
        seenInvoices.add(idKey);
      }

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

        final rawQty = (map['qty'] as num?)?.toInt() ?? 0;
        // Returns may already store negative qty (-q) in itemsJson. Taking abs() guarantees
        // that sign (-1 for return, +1 for sale) reliably controls addition vs subtraction.
        final qty = rawQty.abs();
        final unitPrice = (map['unitPrice'] as num?)?.toDouble() ?? 0;
        final rawLineTotal = (map['lineTotal'] as num?)?.toDouble() ?? (qty * unitPrice);
        final lineTotal = rawLineTotal.abs();
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
