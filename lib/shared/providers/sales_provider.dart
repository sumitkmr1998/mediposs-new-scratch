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
import '../services/firebase_sync_service.dart';
import '../../objectbox.g.dart';
import 'inventory_provider.dart';

enum SalesFilter { today, yesterday, last7Days, allTime, custom }

class SalesProvider extends ChangeNotifier {
  List<Sale> _sales = [];
  List<Sale> _rawSales = [];
  List<Sale> get sales => List.unmodifiable(_sales);
  List<Sale> get rawSales => List.unmodifiable(_rawSales);

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

  double getConsultationTotal(Sale sale) {
    try {
      final list = jsonDecode(sale.itemsJson) as List;
      return list
          .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
          .where((item) => item.isProcedure && item.medicineName.startsWith('Consultation Fee'))
          .fold(0.0, (sum, item) => sum + item.lineTotal);
    } catch (_) {
      return 0.0;
    }
  }

  double getProcedureTotal(Sale sale) {
    try {
      final list = jsonDecode(sale.itemsJson) as List;
      return list
          .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
          .where((item) => item.isProcedure && !item.medicineName.startsWith('Consultation Fee'))
          .fold(0.0, (sum, item) => sum + item.lineTotal);
    } catch (_) {
      return 0.0;
    }
  }

  double getMedicineTotal(Sale sale) {
    return sale.total - getConsultationTotal(sale) - getProcedureTotal(sale);
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
        .fold(0.0, (sum, s) => sum + getMedicineTotal(s));
  }

  double get filteredRevenue => _sales.fold(0.0, (sum, s) => sum + getMedicineTotal(s));

  double get todayProcedureRevenue {
    final today = DateTime.now();
    return _sales
        .where(
          (s) =>
              s.createdAt.year == today.year &&
              s.createdAt.month == today.month &&
              s.createdAt.day == today.day &&
              !s.isReturn,
        )
        .fold(0.0, (sum, s) => sum + getProcedureTotal(s));
  }

  double get filteredProcedureRevenue {
    return _sales
        .where((s) => !s.isReturn)
        .fold(0.0, (sum, s) => sum + getProcedureTotal(s));
  }

  double get todayConsultationRevenue {
    final today = DateTime.now();
    return _sales
        .where(
          (s) =>
              s.createdAt.year == today.year &&
              s.createdAt.month == today.month &&
              s.createdAt.day == today.day &&
              !s.isReturn,
        )
        .fold(0.0, (sum, s) => sum + getConsultationTotal(s));
  }

  double get filteredConsultationRevenue {
    return _sales
        .where((s) => !s.isReturn)
        .fold(0.0, (sum, s) => sum + getConsultationTotal(s));
  }

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

  double get totalRevenue => _sales.fold(0.0, (sum, s) => sum + getMedicineTotal(s));
  double get totalDiscount => _sales.fold(0.0, (sum, s) => sum + s.discount);

  void load() {
    final box = ObjectBoxService.instance.saleBox;

    final rawQuery = box.query().order(Sale_.createdAt, flags: Order.descending).build();
    _rawSales = rawQuery.find();
    rawQuery.close();

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
    
    // Debug log to compare sales details between Hub and Client
    final details = _sales.map((s) => '${s.invoiceNo}:total=${s.total}:isReturn=${s.isReturn}:isDispense=${s.isClinicalDispense}').toList();
    final rawDetails = _rawSales.map((s) => '${s.invoiceNo}:total=${s.total}:isReturn=${s.isReturn}:createdAt=${s.createdAt.toIso8601String()}').toList();
    debugPrint('SalesProvider: Loaded ${_sales.length} today sales. Details: $details');
    debugPrint('SalesProvider: Total raw sales count: ${_rawSales.length}. Raw details: $rawDetails');
    
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

      final isClient = ObjectBoxService.instance.settings.isWindowsClient;
      final isHub = !ObjectBoxService.instance.settings.isWindowsClient;

      if (isHub) {
        if (LocalServerService.instance.isRunning) {
          LocalServerService.instance.broadcast({'event': 'sync_received'});
          LocalServerService.instance.broadcast({'event': 'medicines_updated'});
        }
        FirebaseSyncService.instance.deleteDocument('sales', sale.invoiceNo);
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
    if (patient.id == 0 && patient.name.isEmpty) return [];

    // Robust matching using local ID, UHID, Phone, and Name:
    // Any strong matching signal is accepted:
    // 1. Same local patientId AND name matches (to verify local consistency)
    // 2. OR same UHID (when both have non-empty UHID)
    // 3. OR same Phone number (when both have non-empty Phone)
    // 4. OR same Name, provided that there is no conflict on UHID or Phone
    
    final allSales = ObjectBoxService.instance.saleBox.getAll();
    return allSales.where((s) {
      final nameMatch = s.patientName.trim().toLowerCase() == patient.name.trim().toLowerCase();
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
