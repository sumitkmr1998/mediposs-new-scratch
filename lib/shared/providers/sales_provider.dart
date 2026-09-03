import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/audit_service.dart';
import '../repositories/sale_repository.dart';
import '../services/sales_fact_service.dart';
import '../services/mutation_service.dart';
import '../../objectbox.g.dart';
import 'inventory_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SalesFilter { today, yesterday, last7Days, allTime, custom }

class SalesProvider extends ChangeNotifier {
  final SaleRepository _repo = SaleRepository();

  List<Sale> _sales = [];
  /// Cached last-N-days sales for analytics (never unbounded history).
  List<Sale>? _analyticsWindow;
  int? _analyticsWindowDays;

  List<Sale> get sales => List.unmodifiable(_sales);

  /// Prefer [salesForAnalytics] with an explicit window.
  /// Defaults to last 90 days (not full multi-year history).
  List<Sale> get rawSales => salesForAnalytics(days: 90);

  /// Sales for velocity / smart-stock / charts. Always range-bounded.
  List<Sale> salesForAnalytics({int days = 30}) {
    if (_analyticsWindow != null && _analyticsWindowDays == days) {
      return List.unmodifiable(_analyticsWindow!);
    }
    _analyticsWindow = _repo.salesLastDays(days);
    _analyticsWindowDays = days;
    return List.unmodifiable(_analyticsWindow!);
  }

  void invalidateAnalyticsCache() {
    _analyticsWindow = null;
    _analyticsWindowDays = null;
  }

  double _todayRevenue = 0.0;
  double _filteredRevenue = 0.0;
  double _todayProcedureRevenue = 0.0;
  double _filteredProcedureRevenue = 0.0;
  double _todayConsultationRevenue = 0.0;
  double _filteredConsultationRevenue = 0.0;
  double _filteredCashRevenue = 0.0;
  double _filteredUpiRevenue = 0.0;
  double _filteredCardRevenue = 0.0;
  double _todayCashRevenue = 0.0;
  double _todayUpiRevenue = 0.0;
  double _todayCardRevenue = 0.0;
  int _todaySalesCount = 0;
  double _totalRevenue = 0.0;
  double _totalDiscount = 0.0;

  // Granular KPI metrics for full range
  double _rangeGrossSales = 0.0;
  double _rangeReturns = 0.0;
  double _rangeMedsDiscount = 0.0;
  int _rangeSaleCount = 0;
  int _rangeReturnCount = 0;

  // Granular KPI metrics for Today
  double _todayGrossSales = 0.0;
  double _todayReturns = 0.0;
  double _todayMedsDiscount = 0.0;
  int _todayReturnCount = 0;

  static const int pageSize = 30;
  int _dbOffset = 0;
  int _dbTotalCount = 0;
  bool _dbHasMore = false;

  String _typeFilter = 'all'; // 'all', 'retail', 'dispense'
  String get typeFilter => _typeFilter;

  void setTypeFilter(String filter) {
    if (_typeFilter != filter) {
      _typeFilter = filter;
      // Type filter is applied in-memory on the loaded page set; reload from DB.
      load();
    }
  }

  List<Sale> get _filteredByTypeList {
    if (_typeFilter == 'retail') {
      return _sales.where((s) => !s.isClinicalDispense).toList();
    } else if (_typeFilter == 'dispense') {
      return _sales.where((s) => s.isClinicalDispense).toList();
    }
    return _sales;
  }

  List<Sale> get displayedSales => List.unmodifiable(_filteredByTypeList);
  bool get hasMore => _dbHasMore || _filteredByTypeList.length < _sales.length;
  int get totalCount => _dbTotalCount > 0 ? _dbTotalCount : _filteredByTypeList.length;
  List<Sale> get filteredSales => List.unmodifiable(_filteredByTypeList);

  void loadMore() {
    if (!_dbHasMore) return;
    _fetchPage(append: true);
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

  double getConsultationTotal(Sale sale) => sale.consultationTotal;
  double getProcedureTotal(Sale sale) => sale.procedureTotal;
  double getMedicineTotal(Sale sale) => sale.medicineTotal;

  double get todayRevenue => _todayRevenue;
  double get filteredRevenue => _filteredRevenue;
  double get todayProcedureRevenue => _todayProcedureRevenue;
  double get filteredProcedureRevenue => _filteredProcedureRevenue;
  double get todayConsultationRevenue => _todayConsultationRevenue;
  double get filteredConsultationRevenue => _filteredConsultationRevenue;
  double get filteredCashRevenue => _filteredCashRevenue;
  double get filteredUpiRevenue => _filteredUpiRevenue;
  double get filteredCardRevenue => _filteredCardRevenue;
  double get todayCashRevenue => _todayCashRevenue;
  double get todayUpiRevenue => _todayUpiRevenue;
  double get todayCardRevenue => _todayCardRevenue;
  int get todaySalesCount => _todaySalesCount;
  double get totalRevenue => _totalRevenue;
  double get totalDiscount => _totalDiscount;
  int get filteredSalesCount => totalCount;

  // Granular KPI getters
  double get rangeGrossSales => _rangeGrossSales;
  double get rangeReturns => _rangeReturns;
  double get rangeMedsDiscount => _rangeMedsDiscount;
  int get rangeSaleCount => _rangeSaleCount;
  int get rangeReturnCount => _rangeReturnCount;

  double get todayGrossSales => _todayGrossSales;
  double get todayReturns => _todayReturns;
  double get todayMedsDiscount => _todayMedsDiscount;
  int get todayReturnCount => _todayReturnCount;

  bool _isToday(DateTime dt) {
    final localDt = dt.toLocal();
    final today = DateTime.now();
    return localDt.year == today.year &&
        localDt.month == today.month &&
        localDt.day == today.day;
  }

  void _recalculateTotals() {
    _todayRevenue = 0.0;
    _filteredRevenue = 0.0;
    _todayProcedureRevenue = 0.0;
    _filteredProcedureRevenue = 0.0;
    _todayConsultationRevenue = 0.0;
    _filteredConsultationRevenue = 0.0;
    _filteredCashRevenue = 0.0;
    _filteredUpiRevenue = 0.0;
    _filteredCardRevenue = 0.0;
    _todayCashRevenue = 0.0;
    _todayUpiRevenue = 0.0;
    _todayCardRevenue = 0.0;
    _todaySalesCount = 0;
    _totalRevenue = 0.0;
    _totalDiscount = 0.0;

    _rangeGrossSales = 0.0;
    _rangeReturns = 0.0;
    _rangeMedsDiscount = 0.0;
    _rangeSaleCount = 0;
    _rangeReturnCount = 0;

    _todayGrossSales = 0.0;
    _todayReturns = 0.0;
    _todayMedsDiscount = 0.0;
    _todayReturnCount = 0;

    for (final s in _sales) {
      _accumulateSale(s);
    }
  }

  /// Soft cap when filter is allTime: avoid loading multi-year tables into RAM.
  static const int allTimeLookbackDays = 365;

  DateTime get _effectiveStart {
    if (_customStart != null) return _customStart!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: allTimeLookbackDays));
  }

  DateTime get _effectiveEnd {
    if (_customEnd != null) return _customEnd!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  void load() {
    invalidateAnalyticsCache();
    _dbOffset = 0;
    _sales = [];
    _fetchPage(append: false);
  }

  void _fetchPage({required bool append}) {
    final start = _effectiveStart;
    final end = _effectiveEnd;

    if (!append) {
      _dbTotalCount = _repo.countInRange(start, end);
      // Totals need full range for KPIs — stream in chunks, keep only pages in _sales.
      _recalculateTotalsFromDb(start, end);
    }

    final rawPage = _repo.salesInRange(
      start,
      end,
      limit: pageSize,
      offset: _dbOffset,
    );

    // Filter out duplicates by invoiceNo within current set
    final existingInvoices = _sales.map((s) => s.invoiceNo.trim()).where((inv) => inv.isNotEmpty).toSet();
    final page = <Sale>[];
    for (final s in rawPage) {
      final inv = s.invoiceNo.trim();
      if (inv.isEmpty || !existingInvoices.contains(inv)) {
        page.add(s);
        if (inv.isNotEmpty) existingInvoices.add(inv);
      }
    }

    if (append) {
      _sales = [..._sales, ...page];
    } else {
      _sales = page;
    }
    _dbOffset = _sales.length;
    _dbHasMore = _dbOffset < _dbTotalCount;

    if (!append) {
      try {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(
              'today_revenue', '₹${_todayRevenue.toStringAsFixed(0)}');
          prefs.setInt('today_count', _todaySalesCount);
        });
      } catch (e) {
        debugPrint('SalesProvider: SharedPreferences write failed: $e');
      }
      if (kDebugMode) {
        debugPrint(
            'SalesProvider: page=${_sales.length}/$_dbTotalCount filter=$_activeFilter');
      }
    }

    notifyListeners();
  }

  /// Stream sales in chunks to compute KPIs without holding the full list.
  void _recalculateTotalsFromDb(DateTime start, DateTime end) {
    _todayRevenue = 0.0;
    _filteredRevenue = 0.0;
    _todayProcedureRevenue = 0.0;
    _filteredProcedureRevenue = 0.0;
    _todayConsultationRevenue = 0.0;
    _filteredConsultationRevenue = 0.0;
    _filteredCashRevenue = 0.0;
    _filteredUpiRevenue = 0.0;
    _filteredCardRevenue = 0.0;
    _todayCashRevenue = 0.0;
    _todayUpiRevenue = 0.0;
    _todayCardRevenue = 0.0;
    _todaySalesCount = 0;
    _totalRevenue = 0.0;
    _totalDiscount = 0.0;

    _rangeGrossSales = 0.0;
    _rangeReturns = 0.0;
    _rangeMedsDiscount = 0.0;
    _rangeSaleCount = 0;
    _rangeReturnCount = 0;

    _todayGrossSales = 0.0;
    _todayReturns = 0.0;
    _todayMedsDiscount = 0.0;
    _todayReturnCount = 0;

    const chunk = 500;
    var offset = 0;
    final seenInvoices = <String>{};
    while (true) {
      final batch = _repo.salesInRange(start, end, limit: chunk, offset: offset);
      if (batch.isEmpty) break;
      for (final s in batch) {
        final inv = s.invoiceNo.trim();
        if (inv.isEmpty || !seenInvoices.contains(inv)) {
          _accumulateSale(s);
          if (inv.isNotEmpty) seenInvoices.add(inv);
        }
      }
      offset += batch.length;
      if (batch.length < chunk) break;
    }
  }

  void _accumulateSale(Sale s) {
    // Check type filter match
    if (_typeFilter == 'retail' && s.isClinicalDispense) return;
    if (_typeFilter == 'dispense' && !s.isClinicalDispense) return;

    final isTodaySale = _isToday(s.createdAt);
    final med = s.medicineTotal;
    final cons = s.consultationTotal;
    final proc = s.procedureTotal;

    _totalDiscount += s.discount;

    // Granular range totals
    if (s.isReturn) {
      _rangeReturns += med.abs();
      _rangeReturnCount++;
    } else {
      _rangeGrossSales += med;
      _rangeMedsDiscount += s.discount.abs();
      _rangeSaleCount++;
    }

    if (isTodaySale) {
      _todayRevenue += med;
      _todaySalesCount++;
      if (s.isReturn) {
        _todayReturns += med.abs();
        _todayReturnCount++;
      } else {
        _todayGrossSales += med;
        _todayMedsDiscount += s.discount.abs();
        _todayProcedureRevenue += proc;
        _todayConsultationRevenue += cons;
      }
      if (s.paymentMethod == 'mixed') {
        _todayCashRevenue += s.cashAmount;
        _todayUpiRevenue += s.upiAmount;
        _todayCardRevenue += s.cardAmount;
      } else if (s.paymentMethod == 'cash') {
        _todayCashRevenue += s.total;
      } else if (s.paymentMethod == 'upi') {
        _todayUpiRevenue += s.total;
      } else if (s.paymentMethod == 'card') {
        _todayCardRevenue += s.total;
      }
    }

    _filteredRevenue += med;
    _totalRevenue += med;
    if (!s.isReturn) {
      _filteredProcedureRevenue += proc;
      _filteredConsultationRevenue += cons;
    }
    if (s.paymentMethod == 'mixed') {
      _filteredCashRevenue += s.cashAmount;
      _filteredUpiRevenue += s.upiAmount;
      _filteredCardRevenue += s.cardAmount;
    } else if (s.paymentMethod == 'cash') {
      _filteredCashRevenue += s.total;
    } else if (s.paymentMethod == 'upi') {
      _filteredUpiRevenue += s.total;
    } else if (s.paymentMethod == 'card') {
      _filteredCardRevenue += s.total;
    }
  }

  void search(String term) {
    _searchQuery = term;
    if (term.isEmpty) {
      load();
      return;
    }

    final rawResults = _repo.search(term: term, limit: 100);
    final seen = <String>{};
    final deduped = <Sale>[];
    for (final s in rawResults) {
      final inv = s.invoiceNo.trim();
      if (inv.isEmpty || !seen.contains(inv)) {
        deduped.add(s);
        if (inv.isNotEmpty) seen.add(inv);
      }
    }
    _sales = deduped;
    _dbOffset = _sales.length;
    _dbTotalCount = _sales.length;
    _dbHasMore = false;
    // Totals for search results only (bounded).
    _recalculateTotals();
    notifyListeners();
  }

  void deleteSale(Sale sale, InventoryProvider inv, {SyncService? syncService, AppUser? actor}) {
    try {
      final items = getSaleItems(sale);
      for (final item in items) {
        if (item.medicineId <= 0) continue; // Skip consultation fees, procedures, etc.
        // Reverses the inventory action identically
        // (Returns natively have negative qty, Sales have positive qty)
        if (sale.isClinicalDispense) {
          inv.deductClinicStock(item.medicineId, -item.qty);
        } else {
          inv.deductStoreStock(item.medicineId, -item.qty);
        }
      }
      int idToDelete = sale.id;
      if (idToDelete == 0 && sale.invoiceNo.isNotEmpty) {
        final existing = ObjectBoxService.instance.saleBox
            .query(Sale_.invoiceNo.equals(sale.invoiceNo))
            .build()
            .findFirst();
        if (existing != null) {
          idToDelete = existing.id;
        }
      }

      if (idToDelete > 0) {
        try {
          SalesFactService.instance.reverseSale(sale);
        } catch (e) {
          debugPrint('SalesProvider: fact reverse failed: $e');
        }
        ObjectBoxService.instance.saleBox.remove(idToDelete);
      } else {
        debugPrint('Warning: Could not find sale to delete by ID or invoiceNo');
      }

      // Log voided sale
      AuditService.instance.log(
        action: 'VOID',
        entityType: 'Sale',
        entityId: sale.invoiceNo,
        description: 'Voided/Deleted Sale (Invoice: ${sale.invoiceNo}), refunded ₹${sale.total}',
        details: {
          'invoiceNo': sale.invoiceNo,
          'total': sale.total,
          'isReturn': sale.isReturn,
          'patientName': sale.patientName,
        },
        actor: actor,
      );

      load();

      MutationService.instance.publish(
        entity: 'sale',
        action: 'delete',
        data: {'invoiceNo': sale.invoiceNo},
        hubEvents: const ['sync_received', 'medicines_updated', 'sale_deleted'],
        hubPayload: {'invoiceNo': sale.invoiceNo},
      );
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

  List<Sale> getSalesForPatient(Patient patient) {
    final name = patient.name.trim();
    if (name.isEmpty) return [];

    // Robust matching using local ID, UHID, Phone, and Name:
    // Any strong matching signal is accepted:
    // 1. Same local patientId AND name matches (to verify local consistency)
    // 2. OR same UHID (when both have non-empty UHID)
    // 3. OR same Phone number (when both have non-empty Phone)
    // 4. OR same Name, provided that there is no conflict on UHID or Phone
    
    final matchingSales = ObjectBoxService.instance.saleBox
        .query(Sale_.patientName.equals(name, caseSensitive: false))
        .build()
        .find();
    return matchingSales.where((s) {
      final nameMatch = s.patientName.trim().toLowerCase() == name.toLowerCase();
      if (!nameMatch) return false; // Name must always match to prevent collision

      final idMatch = s.patientId == patient.id;
      if (idMatch) return true; // Name and Local ID matches
      
      final hasUhid = patient.uhid.isNotEmpty && s.patientUhid.isNotEmpty;
      final uhidMatch = hasUhid && s.patientUhid.trim().toLowerCase() == patient.uhid.trim().toLowerCase();
      if (uhidMatch) return true; // UHID matches
      
      final hasPhone = patient.phone.isNotEmpty && s.patientPhone.isNotEmpty;
      final phoneMatch = hasPhone && s.patientPhone.trim() == patient.phone.trim();
      if (phoneMatch) return true; // Phone matches

      // If we don't have matching IDs, UHIDs, or Phones:
      // We allow matching by Name only IF there are no conflicting UHIDs or Phones.
      final uhidConflict = hasUhid && !uhidMatch;
      final phoneConflict = hasPhone && !phoneMatch;
      if (!uhidConflict && !phoneConflict) return true;

      return false;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
