import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/audit_service.dart';
import '../../objectbox.g.dart';
import 'inventory_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SalesFilter { today, yesterday, last7Days, allTime, custom }

class SalesProvider extends ChangeNotifier {
  List<Sale> _sales = [];
  List<Sale>? _rawSales;
  List<Sale> get sales => List.unmodifiable(_sales);
  List<Sale> get rawSales {
    if (_rawSales == null) {
      final box = ObjectBoxService.instance.saleBox;
      final rawQuery = box.query().order(Sale_.createdAt, flags: Order.descending).build();
      _rawSales = rawQuery.find();
      rawQuery.close();
    }
    return List.unmodifiable(_rawSales!);
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

  static const int pageSize = 30;
  int _loadedCount = 30;

  String _typeFilter = 'all'; // 'all', 'retail', 'dispense'
  String get typeFilter => _typeFilter;

  void setTypeFilter(String filter) {
    if (_typeFilter != filter) {
      _typeFilter = filter;
      _loadedCount = pageSize;
      notifyListeners();
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

  List<Sale> get displayedSales =>
      List.unmodifiable(_filteredByTypeList.take(_loadedCount).toList());
  bool get hasMore => _loadedCount < _filteredByTypeList.length;
  int get totalCount => _filteredByTypeList.length;
  List<Sale> get filteredSales => List.unmodifiable(_filteredByTypeList);

  void loadMore() {
    if (!hasMore) return;
    _loadedCount = (_loadedCount + pageSize).clamp(0, _filteredByTypeList.length);
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
  int get filteredSalesCount => _sales.length;

  bool _isToday(DateTime dt) {
    final localDt = dt.toLocal();
    final today = DateTime.now();
    return localDt.year == today.year &&
        localDt.month == today.month &&
        localDt.day == today.day;
  }

  void _recalculateTotals() {
    final today = DateTime.now();
    
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

    for (final s in _sales) {
      final isTodaySale = _isToday(s.createdAt);
      
      final med = s.medicineTotal;
      final cons = s.consultationTotal;
      final proc = s.procedureTotal;

      _totalDiscount += s.discount;

      if (isTodaySale) {
        _todayRevenue += med;
        _todaySalesCount++;
        
        if (!s.isReturn) {
          _todayProcedureRevenue += proc;
          _todayConsultationRevenue += cons;
        }

        // Today payment method breakdown
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

      // Filtered payment method breakdown
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
  }

  void load() {
    _rawSales = null; // Invalidate lazy cache
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
    _recalculateTotals();

    try {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('today_revenue', '₹${_todayRevenue.toStringAsFixed(0)}');
        prefs.setInt('today_count', _todaySalesCount);
      });
    } catch (e) {
      debugPrint('SalesProvider: SharedPreferences write failed: $e');
    }
    
    // Debug log to compare sales details between Hub and Client
    final details = _sales.map((s) => '${s.invoiceNo}:total=${s.total}:isReturn=${s.isReturn}:isDispense=${s.isClinicalDispense}').toList();
    debugPrint('SalesProvider: Loaded ${_sales.length} today sales. Details: $details');
    
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

      final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;

      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      } else if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'sale',
          action: 'delete',
          data: {'invoiceNo': sale.invoiceNo},
        );
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
