import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/daily_medicine_sales_fact.dart';
import '../models/sale.dart';
import '../utils/consumption_aggregator.dart';
import 'objectbox_service.dart';
import '../../objectbox.g.dart';

/// Maintains [DailyMedicineSalesFact] for O(SKUs) analytics without decoding sale JSON.
class SalesFactService {
  static final SalesFactService instance = SalesFactService._();
  SalesFactService._();

  Box<DailyMedicineSalesFact> get _box =>
      ObjectBoxService.instance.salesFactBox;

  static int dayEpochMs(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day).millisecondsSinceEpoch;
  }

  /// Apply sale lines to daily facts (sign -1 for returns / voids of positive sales).
  void applySale(Sale sale, {int sign = 1}) {
    if (!ObjectBoxService.isInitialized) return;
    final day = dayEpochMs(sale.createdAt);
    final effectiveSign = sale.isReturn ? -sign : sign;

    List items;
    try {
      items = jsonDecode(sale.itemsJson) as List;
    } catch (_) {
      return;
    }

    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['isProcedure'] == true) continue;

      final name = (map['medicineName'] as String? ?? '').toLowerCase().trim();
      if (name.isEmpty) continue;
      final qty = (map['qty'] as num?)?.toInt() ?? 0;
      final unitPrice = (map['unitPrice'] as num?)?.toDouble() ?? 0;
      final lineTotal =
          (map['lineTotal'] as num?)?.toDouble() ?? (qty * unitPrice);
      final medicineId = (map['medicineId'] as num?)?.toInt() ?? 0;

      _bump(
        dayEpochMs: day,
        medicineId: medicineId,
        nameKey: name,
        qtyDelta: effectiveSign * qty,
        revenueDelta: effectiveSign * lineTotal,
      );
    }
  }

  void reverseSale(Sale sale) => applySale(sale, sign: -1);

  void _bump({
    required int dayEpochMs,
    required int medicineId,
    required String nameKey,
    required int qtyDelta,
    required double revenueDelta,
  }) {
    Condition<DailyMedicineSalesFact>? cond =
        DailyMedicineSalesFact_.dayEpochMs.equals(dayEpochMs);
    if (medicineId > 0) {
      cond = cond.and(DailyMedicineSalesFact_.medicineId.equals(medicineId));
    } else {
      cond =
          cond.and(DailyMedicineSalesFact_.medicineNameKey.equals(nameKey));
    }

    final q = _box.query(cond).build();
    DailyMedicineSalesFact? existing;
    try {
      existing = q.findFirst();
    } finally {
      q.close();
    }

    if (existing == null) {
      _box.put(DailyMedicineSalesFact(
        dayEpochMs: dayEpochMs,
        medicineId: medicineId,
        medicineNameKey: nameKey,
        qtySold: qtyDelta,
        revenue: revenueDelta,
      ));
    } else {
      existing.qtySold += qtyDelta;
      existing.revenue += revenueDelta;
      if (existing.medicineId == 0 && medicineId > 0) {
        existing.medicineId = medicineId;
      }
      _box.put(existing);
    }
  }

  /// Units sold over the last [days] ending today (local).
  ConsumptionResult consumptionLastDays(int days) {
    final now = DateTime.now();
    final endDay = DateTime(now.year, now.month, now.day);
    final startDay = endDay.subtract(Duration(days: days - 1));
    return consumptionInRange(startDay, endDay);
  }

  ConsumptionResult consumptionInRange(DateTime startDay, DateTime endDay) {
    final start = DateTime(startDay.year, startDay.month, startDay.day)
        .millisecondsSinceEpoch;
    final end = DateTime(endDay.year, endDay.month, endDay.day)
        .millisecondsSinceEpoch;

    final q = _box
        .query(DailyMedicineSalesFact_.dayEpochMs.between(start, end))
        .build();
    List<DailyMedicineSalesFact> rows;
    try {
      rows = q.find();
    } finally {
      q.close();
    }

    final unitsByName = <String, int>{};
    final revenueByName = <String, double>{};
    final unitsById = <int, int>{};
    final revenueById = <int, double>{};

    for (final r in rows) {
      if (r.medicineNameKey.isNotEmpty) {
        unitsByName[r.medicineNameKey] =
            (unitsByName[r.medicineNameKey] ?? 0) + r.qtySold;
        revenueByName[r.medicineNameKey] =
            (revenueByName[r.medicineNameKey] ?? 0) + r.revenue;
      }
      if (r.medicineId > 0) {
        unitsById[r.medicineId] = (unitsById[r.medicineId] ?? 0) + r.qtySold;
        revenueById[r.medicineId] =
            (revenueById[r.medicineId] ?? 0) + r.revenue;
      }
    }

    return ConsumptionResult(
      unitsByName: unitsByName,
      revenueByName: revenueByName,
      unitsById: unitsById,
      revenueById: revenueById,
    );
  }

  bool get hasAnyFacts => _box.count() > 0;

  /// Chunked backfill from raw sales (migration). Clears existing facts first if [clearFirst].
  int backfillFromSales({bool clearFirst = true, int chunkSize = 500}) {
    final saleBox = ObjectBoxService.instance.saleBox;
    if (clearFirst) {
      _box.removeAll();
    }

    var offset = 0;
    var processed = 0;
    while (true) {
      final q = saleBox
          .query()
          .order(Sale_.createdAt)
          .build();
      try {
        q.offset = offset;
        q.limit = chunkSize;
        final batch = q.find();
        if (batch.isEmpty) break;
        for (final s in batch) {
          applySale(s);
          processed++;
        }
        offset += batch.length;
        if (batch.length < chunkSize) break;
      } finally {
        q.close();
      }
    }
    debugPrint('SalesFactService: backfilled $processed sales into facts');
    return processed;
  }
}
