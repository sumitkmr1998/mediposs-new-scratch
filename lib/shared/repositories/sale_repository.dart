import '../models/sale.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';

/// ObjectBox access for sales — ranged queries and pagination only.
class SaleRepository {
  Box<Sale> get _box => ObjectBoxService.instance.saleBox;

  /// Sales with [createdAt] in [start, end] inclusive, newest first.
  List<Sale> salesInRange(
    DateTime start,
    DateTime end, {
    int? limit,
    int offset = 0,
  }) {
    final query = _box
        .query(
          Sale_.createdAt.between(
            start.millisecondsSinceEpoch,
            end.millisecondsSinceEpoch,
          ),
        )
        .order(Sale_.createdAt, flags: Order.descending)
        .build();
    try {
      if (offset > 0) query.offset = offset;
      if (limit != null && limit > 0) query.limit = limit;
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Count of sales in range (for pagination UI).
  int countInRange(DateTime start, DateTime end) {
    final query = _box
        .query(
          Sale_.createdAt.between(
            start.millisecondsSinceEpoch,
            end.millisecondsSinceEpoch,
          ),
        )
        .build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  /// Last [days] calendar days ending now (local).
  List<Sale> salesLastDays(int days, {int? limit}) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final startDay = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return salesInRange(startDay, end, limit: limit);
  }

  List<Sale> search({
    required String term,
    int limit = 50,
    int offset = 0,
  }) {
    final q = term.trim();
    if (q.isEmpty) return [];
    final query = _box
        .query(
          Sale_.patientName
              .contains(q, caseSensitive: false)
              .or(Sale_.invoiceNo.contains(q, caseSensitive: false))
              .or(Sale_.patientPhone.contains(q, caseSensitive: false)),
        )
        .order(Sale_.createdAt, flags: Order.descending)
        .build();
    try {
      query.offset = offset;
      query.limit = limit;
      return query.find();
    } finally {
      query.close();
    }
  }

  /// All sales ordered newest first — **avoid for UI**. Use only migrations/export.
  List<Sale> findAllOrdered({int? limit, int offset = 0}) {
    final query =
        _box.query().order(Sale_.createdAt, flags: Order.descending).build();
    try {
      if (offset > 0) query.offset = offset;
      if (limit != null && limit > 0) query.limit = limit;
      return query.find();
    } finally {
      query.close();
    }
  }

  void invalidateNote() {
    // Callers should drop any local caches when sales change.
  }
}
