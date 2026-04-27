import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../services/objectbox_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../../objectbox.g.dart';
import 'inventory_provider.dart';

enum SalesFilter { today, yesterday, last7Days, allTime, custom }

class SalesProvider extends ChangeNotifier {
  List<Sale> _sales = [];
  List<Sale> get sales => List.unmodifiable(_sales);

  static const int pageSize = 30;
  int _loadedCount = 30;

  List<Sale> get displayedSales =>
      List.unmodifiable(_sales.take(_loadedCount).toList());
  bool get hasMore => _loadedCount < _sales.length;
  int get totalCount => _sales.length;

  void loadMore() {
    if (!hasMore) return;
    _loadedCount = (_loadedCount + pageSize).clamp(0, _sales.length);
    notifyListeners();
  }

  SalesFilter _activeFilter = SalesFilter.allTime;
  DateTime? _customStart;
  DateTime? _customEnd;

  SalesFilter get activeFilter => _activeFilter;
  DateTime? get customStart => _customStart;
  DateTime? get customEnd => _customEnd;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  bool get isSearching => _searchQuery.isNotEmpty;

  SalesProvider() {
    _activeFilter = SalesFilter.today;
    _setToday();
  }

  void _setToday() {
    final now = DateTime.now();
    _customStart = DateTime(now.year, now.month, now.day);
    _customEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  void setFilter(SalesFilter filter, {DateTimeRange? range}) {
    _activeFilter = filter;
    final now = DateTime.now();

    switch (filter) {
      case SalesFilter.today:
        _setToday();
        break;
      case SalesFilter.yesterday:
        final yest = now.subtract(const Duration(days: 1));
        _customStart = DateTime(yest.year, yest.month, yest.day);
        _customEnd = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
        break;
      case SalesFilter.last7Days:
        final start = now.subtract(const Duration(days: 6));
        _customStart = DateTime(start.year, start.month, start.day);
        _customEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case SalesFilter.allTime:
        _customStart = null;
        _customEnd = null;
        break;
      case SalesFilter.custom:
        if (range != null) {
          _customStart = range.start;
          _customEnd = DateTime(
            range.end.year,
            range.end.month,
            range.end.day,
            23,
            59,
            59,
          );
        }
        break;
    }
    load();
  }

  double get todayRevenue {
    final today = DateTime.now();
    return _sales
        .where(
          (s) =>
              s.createdAt.year == today.year &&
              s.createdAt.month == today.month &&
              s.createdAt.day == today.day,
        )
        .fold(0.0, (sum, s) => sum + s.total);
  }

  double get filteredRevenue => _sales.fold(0.0, (sum, s) => sum + s.total);

  double get filteredCashRevenue {
    return _sales.fold(0.0, (sum, s) {
      if (s.paymentMethod == 'mixed') return sum + s.cashAmount;
      if (s.paymentMethod == 'cash') return sum + s.total;
      return sum;
    });
  }

  double get filteredUpiRevenue {
    return _sales.fold(0.0, (sum, s) {
      if (s.paymentMethod == 'mixed') return sum + s.upiAmount;
      if (s.paymentMethod == 'upi') return sum + s.total;
      return sum;
    });
  }

  double get filteredCardRevenue {
    return _sales.fold(0.0, (sum, s) {
      if (s.paymentMethod == 'mixed') return sum + s.cardAmount;
      if (s.paymentMethod == 'card') return sum + s.total;
      return sum;
    });
  }

  int get filteredSalesCount => _sales.length;

  double get todayCashRevenue {
    return _sales.where((s) => _isToday(s.createdAt)).fold(0.0, (sum, s) {
      if (s.paymentMethod == 'mixed') return sum + s.cashAmount;
      if (s.paymentMethod == 'cash') return sum + s.total;
      return sum;
    });
  }

  double get todayUpiRevenue {
    return _sales.where((s) => _isToday(s.createdAt)).fold(0.0, (sum, s) {
      if (s.paymentMethod == 'mixed') return sum + s.upiAmount;
      if (s.paymentMethod == 'upi') return sum + s.total;
      return sum;
    });
  }

  double get todayCardRevenue {
    return _sales.where((s) => _isToday(s.createdAt)).fold(0.0, (sum, s) {
      if (s.paymentMethod == 'mixed') return sum + s.cardAmount;
      if (s.paymentMethod == 'card') return sum + s.total;
      return sum;
    });
  }

  bool _isToday(DateTime dt) {
    final today = DateTime.now();
    return dt.year == today.year &&
        dt.month == today.month &&
        dt.day == today.day;
  }

  int get todaySalesCount {
    final today = DateTime.now();
    return _sales
        .where(
          (s) =>
              s.createdAt.year == today.year &&
              s.createdAt.month == today.month &&
              s.createdAt.day == today.day,
        )
        .length;
  }

  double get totalRevenue => _sales.fold(0.0, (sum, s) => sum + s.total);

  void load() {
    final box = ObjectBoxService.instance.saleBox;

    Query<Sale> query;
    if (_customStart != null && _customEnd != null) {
      query = box
          .query(
            Sale_.createdAt.between(
              _customStart!.millisecondsSinceEpoch,
              _customEnd!.millisecondsSinceEpoch,
            ),
          )
          .order(Sale_.createdAt, flags: Order.descending)
          .build();
    } else {
      query =
          box.query().order(Sale_.createdAt, flags: Order.descending).build();
    }

    _sales = query.find();
    _loadedCount = pageSize;
    query.close();
    notifyListeners();
  }

  void search(String term) {
    _searchQuery = term;
    if (term.isEmpty) {
      load();
      return;
    }

    final box = ObjectBoxService.instance.saleBox;
    final query = box
        .query(
          Sale_.patientName
              .contains(_searchQuery, caseSensitive: false)
              .or(Sale_.invoiceNo.contains(_searchQuery, caseSensitive: false))
              .or(Sale_.patientPhone
                  .contains(_searchQuery, caseSensitive: false)),
        )
        .order(Sale_.createdAt, flags: Order.descending)
        .build();

    _sales = query.find();
    _loadedCount = pageSize;
    query.close();
    notifyListeners();
  }

  void deleteSale(Sale sale, InventoryProvider inv, {SyncService? syncService}) {
    try {
      final items = getSaleItems(sale);
      for (final item in items) {
        // Reverses the inventory action identically
        // (Returns natively have negative qty, Sales have positive qty)
        inv.deductStoreStock(item.medicineId, -item.qty);
      }
      ObjectBoxService.instance.saleBox.remove(sale.id);
      load();

      if (Platform.isWindows && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      } else if (Platform.isAndroid && syncService != null) {
        syncService.pushSaleDelete(sale.invoiceNo);
      }
    } catch (e) {
      debugPrint('Error deleting sale: $e');
    }
  }

  List<SaleItem> getSaleItems(Sale sale) {
    try {
      final list = jsonDecode(sale.itemsJson) as List;
      return list
          .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<Sale> getSalesByPatient(int patientId) {
    if (patientId == 0) return [];
    return ObjectBoxService.instance.saleBox
        .query(Sale_.patientId.equals(patientId))
        .order(Sale_.createdAt, flags: Order.descending)
        .build()
        .find();
  }
}
