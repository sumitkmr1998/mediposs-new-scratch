import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../models/medicine.dart';
import '../services/hub_service.dart';
import '../services/data_persistence_service.dart';

class HubProvider extends ChangeNotifier {
  final HubService _service = HubService();
  final DataPersistenceService _persistence = DataPersistenceService.instance;

  List<Sale> _sales = [];
  List<Medicine> _medicines = [];

  bool _isLoading = true;
  bool _isUpdatingFromHub = false;
  String _error = '';
  DateTime? _lastUpdateTime;

  List<Sale> get sales => _sales;
  List<Medicine> get medicines => _medicines;
  bool get isLoading => _isLoading;
  bool get isUpdatingFromHub => _isUpdatingFromHub;
  String get error => _error;
  bool get isConfigured => _service.isConfigured;
  HubService get service => _service;
  DateTime? get lastUpdateTime => _lastUpdateTime;

  Future<void> init() async {
    await _service.loadConfig();
    
    await _loadFromDatabase();
    
    if (isConfigured) {
      _isLoading = false;
      notifyListeners();
      await _updateFromHub();
    } else {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFromDatabase() async {
    try {
      _medicines = await _persistence.loadMedicines();
      _sales = await _persistence.loadSales();
      _lastUpdateTime = await _persistence.getLastUpdateTime();
    } catch (e) {
      debugPrint('Error loading from database: $e');
    }
  }

  Future<void> _updateFromHub() async {
    if (_isUpdatingFromHub) return;
    
    _isUpdatingFromHub = true;
    notifyListeners();

    try {
      final newSales = await _service.getSales();
      final newMedicines = await _service.getMedicines();

      if (newSales.isNotEmpty || newMedicines.isNotEmpty) {
        await _persistence.saveMedicines(newMedicines);
        await _persistence.saveSales(newSales);
        
        _medicines = newMedicines;
        _sales = newSales;
        _lastUpdateTime = DateTime.now();
        _error = '';
      }
    } catch (e) {
      if (_sales.isEmpty && _medicines.isEmpty) {
        _error = 'Unable to fetch data from Hub and no cached data available';
      } else {
        _error = '';
      }
    } finally {
      _isUpdatingFromHub = false;
      notifyListeners();
    }
  }

  Future<bool> login(String ip, String pin) async {
    _isUpdatingFromHub = true;
    _error = '';
    notifyListeners();

    final success = await _service.login(ip, pin);
    if (success) {
      await refreshData();
      return true;
    } else {
      _error = 'Failed to connect. Check IP and PIN.';
      _isUpdatingFromHub = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshData() async {
    await _updateFromHub();
  }

  // ========== ANALYTICS HELPERS ==========

  /// Total revenue (excluding returns)
  double get totalRevenue =>
      _sales.fold(0.0, (sum, s) => sum + (s.isReturn ? -s.total : s.total));

  /// Total cost of goods sold (from items)
  double get totalCost {
    double cost = 0;
    for (final sale in _sales) {
      if (sale.isReturn) continue;
      for (final item in sale.items) {
        final med = _medicines
            .where((m) => m.id == item.medicineId)
            .firstOrNull;
        if (med != null) {
          cost += med.purchasePrice * item.qty;
        }
      }
    }
    return cost;
  }

  double get totalProfit => totalRevenue - totalCost;

  /// Get all sale items for a specific medicine
  List<SaleItem> salesForMedicine(int medicineId) {
    final items = <SaleItem>[];
    for (final sale in _sales) {
      if (sale.isReturn) continue;
      for (final item in sale.items) {
        if (item.medicineId == medicineId) {
          items.add(item);
        }
      }
    }
    return items;
  }

  /// Total units sold for a medicine
  int totalUnitsSold(int medicineId) {
    return salesForMedicine(medicineId).fold(0, (sum, i) => sum + i.qty);
  }

  /// Total revenue for a medicine
  double revenueForMedicine(int medicineId) {
    return salesForMedicine(
      medicineId,
    ).fold(0.0, (sum, i) => sum + i.lineTotal);
  }

  /// Average daily consumption (units/day) over the data period
  double dailyConsumption(int medicineId) {
    if (_sales.isEmpty) return 0;
    final sorted = _sales.where((s) => !s.isReturn).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (sorted.isEmpty) return 0;

    final firstDate = sorted.first.createdAt;
    final lastDate = sorted.last.createdAt;
    final days = lastDate.difference(firstDate).inDays;
    if (days <= 0) return totalUnitsSold(medicineId).toDouble();

    return totalUnitsSold(medicineId) / days;
  }

  /// Estimated days of stock remaining
  double daysOfStockRemaining(int medicineId) {
    final med = _medicines.where((m) => m.id == medicineId).firstOrNull;
    if (med == null) return 0;
    final daily = dailyConsumption(medicineId);
    if (daily <= 0) return 999; // no sales = infinite stock
    return med.totalStock / daily;
  }

  /// Sales grouped by date for a medicine
  Map<DateTime, int> dailySalesForMedicine(int medicineId) {
    final map = <DateTime, int>{};
    for (final sale in _sales) {
      if (sale.isReturn) continue;
      for (final item in sale.items) {
        if (item.medicineId == medicineId) {
          final day = DateTime(
            sale.createdAt.year,
            sale.createdAt.month,
            sale.createdAt.day,
          );
          map[day] = (map[day] ?? 0) + item.qty;
        }
      }
    }
    return map;
  }

  /// Revenue grouped by date
  Map<DateTime, double> dailyRevenue() {
    final map = <DateTime, double>{};
    for (final sale in _sales) {
      final day = DateTime(
        sale.createdAt.year,
        sale.createdAt.month,
        sale.createdAt.day,
      );
      final amount = sale.isReturn ? -sale.total : sale.total;
      map[day] = (map[day] ?? 0) + amount;
    }
    return map;
  }

  /// Dead stock: medicines with zero sales
  List<Medicine> deadStock({int daysSinceLastSale = 30}) {
    final cutoff = DateTime.now().subtract(Duration(days: daysSinceLastSale));
    final soldIds = <int>{};
    for (final sale in _sales) {
      if (sale.createdAt.isAfter(cutoff) && !sale.isReturn) {
        for (final item in sale.items) {
          soldIds.add(item.medicineId);
        }
      }
    }
    return _medicines
        .where((m) => !soldIds.contains(m.id) && m.storeStock > 0)
        .toList();
  }

  /// Category-wise revenue
  Map<String, double> revenueByCategory() {
    final map = <String, double>{};
    for (final sale in _sales) {
      if (sale.isReturn) continue;
      for (final item in sale.items) {
        final med = _medicines
            .where((m) => m.id == item.medicineId)
            .firstOrNull;
        final cat = med?.category ?? 'General';
        map[cat] = (map[cat] ?? 0) + item.lineTotal;
      }
    }
    return map;
  }

  /// Top customers by spend
  List<MapEntry<String, double>> topCustomers({int limit = 10}) {
    final map = <String, double>{};
    for (final sale in _sales) {
      if (sale.isReturn) continue;
      map[sale.patientName] = (map[sale.patientName] ?? 0) + sale.total;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Get first and last sale date for a medicine
  DateTimeRange? dateRangeForMedicine(int medicineId) {
    final mSales = _sales.where((s) {
      if (s.isReturn) return false;
      return s.items.any((i) => i.medicineId == medicineId);
    }).toList();
    if (mSales.isEmpty) return null;
    mSales.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return DateTimeRange(
      start: mSales.first.createdAt,
      end: mSales.last.createdAt,
    );
  }

  // ========== SALES ANALYSIS FOR AI ==========

  /// Get sales trend data for a configurable time period
  /// Returns: Map with date, revenue, unitsSold, transactions
  Map<DateTime, Map<String, dynamic>> getSalesTrend({
    DateTime? startDate,
    DateTime? endDate,
    int? daysBack,
  }) {
    final map = <DateTime, Map<String, dynamic>>{};
    
    // Determine date range
    DateTime start = startDate ?? DateTime.now().subtract(
      daysBack != null ? Duration(days: daysBack) : const Duration(days: 30)
    );
    DateTime end = endDate ?? DateTime.now();
    
    // Initialize daily data
    for (var date = start; date.isBefore(end) || date == end; date = date.add(const Duration(days: 1))) {
      final dayKey = DateTime(date.year, date.month, date.day);
      map[dayKey] = {
        'revenue': 0.0,
        'unitsSold': 0,
        'transactions': 0,
      };
    }
    
    // Populate with sales data
    for (final sale in _sales) {
      if (sale.isReturn) continue;
      if (sale.createdAt.isBefore(start) || sale.createdAt.isAfter(end)) continue;
      
      final dayKey = DateTime(
        sale.createdAt.year,
        sale.createdAt.month,
        sale.createdAt.day,
      );
      
      if (map.containsKey(dayKey)) {
        map[dayKey]!['revenue'] = (map[dayKey]!['revenue'] as double) + sale.total;
        map[dayKey]!['unitsSold'] = (map[dayKey]!['unitsSold'] as int) + 
            sale.items.fold(0, (sum, item) => sum + item.qty);
        map[dayKey]!['transactions'] = (map[dayKey]!['transactions'] as int) + 1;
      }
    }
    
    return map;
  }

  /// Get top medicines by configurable criteria
  List<Map<String, dynamic>> getTopMedicines({
    int limit = 10,
    String sortBy = 'revenue', // 'revenue', 'units', 'profit', 'profitMargin'
    int daysBack = 30,
  }) {
    final start = DateTime.now().subtract(Duration(days: daysBack));
    final end = DateTime.now();
    
    final medicineMetrics = <Map<String, dynamic>>[];
    
    for (final medicine in _medicines) {
      // Get sales for this medicine within the date range
      final periodItems = <SaleItem>[];
      for (final sale in _sales) {
        if (sale.isReturn) continue;
        if (sale.createdAt.isBefore(start) || sale.createdAt.isAfter(end)) continue;
        
        for (final item in sale.items) {
          if (item.medicineId == medicine.id) {
            periodItems.add(item);
          }
        }
      }
      
      if (periodItems.isEmpty) continue;
      
      final unitsSold = periodItems.fold(0, (sum, item) => sum + item.qty);
      final revenue = periodItems.fold(0.0, (sum, item) => sum + item.lineTotal);
      final cost = medicine.purchasePrice * unitsSold;
      final profit = revenue - cost;
      final profitMargin = revenue > 0 ? (profit / revenue) * 100 : 0;
      
      medicineMetrics.add({
        'medicineId': medicine.id,
        'name': medicine.name,
        'category': medicine.category,
        'unitsSold': unitsSold,
        'revenue': revenue,
        'profit': profit,
        'profitMargin': profitMargin,
        'currentStock': medicine.totalStock,
      });
    }
    
    // Sort by requested criteria
    medicineMetrics.sort((a, b) {
      switch (sortBy) {
        case 'units':
          return (b['unitsSold'] as int).compareTo(a['unitsSold'] as int);
        case 'profit':
          return (b['profit'] as double).compareTo(a['profit'] as double);
        case 'profitMargin':
          return (b['profitMargin'] as double).compareTo(a['profitMargin'] as double);
        default: // revenue
          return (b['revenue'] as double).compareTo(a['revenue'] as double);
      }
    });
    
    return medicineMetrics.take(limit).toList();
  }

  /// Get reorder estimates with 45-day target and 30-day critical threshold
  List<Map<String, dynamic>> getReorderEstimates({
    int targetStockDays = 45,
    int criticalThreshold = 30,
    int limit = 20,
  }) {
    final recommendations = <Map<String, dynamic>>[];
    
    for (final medicine in _medicines) {
      final dailyConsumptionVal = dailyConsumption(medicine.id);
      final daysRemaining = daysOfStockRemaining(medicine.id);
      
      // Calculate reorder quantity for target stock days
      final targetStock = dailyConsumptionVal * targetStockDays;
      final reorderQty = (targetStock - medicine.totalStock).ceil();
      
      if (reorderQty > 0 || daysRemaining < targetStockDays) {
        String urgency;
        if (daysRemaining < criticalThreshold) {
          urgency = 'critical';
        } else if (daysRemaining < targetStockDays) {
          urgency = 'warning';
        } else {
          urgency = 'normal';
        }
        
        recommendations.add({
          'medicineId': medicine.id,
          'name': medicine.name,
          'category': medicine.category,
          'dailyConsumption': dailyConsumptionVal,
          'currentStock': medicine.totalStock,
          'daysRemaining': daysRemaining,
          'targetStock': targetStock,
          'reorderQuantity': reorderQty > 0 ? reorderQty : 0,
          'reorderUrgency': urgency,
        });
      }
    }
    
    // Sort by urgency (critical first) then by days remaining
    final urgencyOrder = {'critical': 0, 'warning': 1, 'normal': 2};
    recommendations.sort((a, b) {
      final urgencyDiff = (urgencyOrder[a['reorderUrgency']] ?? 3) - 
                         (urgencyOrder[b['reorderUrgency']] ?? 3);
      if (urgencyDiff != 0) return urgencyDiff;
      return (a['daysRemaining'] as double).compareTo(b['daysRemaining'] as double);
    });
    
    return recommendations.take(limit).toList();
  }

  /// Get recent transactions (anonymized)
  List<Map<String, dynamic>> getRecentTransactions({
    int count = 10,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final transactions = <Map<String, dynamic>>[];
    
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();
    
    for (final sale in _sales) {
      if (sale.isReturn) continue;
      if (sale.createdAt.isBefore(start) || sale.createdAt.isAfter(end)) continue;
      
      transactions.add({
        'id': sale.id,
        'invoiceNo': sale.invoiceNo,
        'patientName': 'Customer ${sale.id % 1000}', // Anonymized
        'total': sale.total,
        'createdAt': sale.createdAt,
        'itemCount': sale.items.length,
        'paymentMethod': sale.paymentMethod,
      });
    }
    
    // Sort by date (most recent first)
    transactions.sort((a, b) => 
      (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));
    
    return transactions.take(count).toList();
  }

  /// Get comprehensive sales summary for AI prompt
  Map<String, dynamic> getSalesSummary({
    int topMedicinesLimit = 10,
    int transactionsCount = 10,
    int targetStockDays = 45,
    int criticalThreshold = 30,
    int salesTrendDays = 30,
  }) {
    final salesTrend = getSalesTrend(daysBack: salesTrendDays);
    final topMedicines = getTopMedicines(limit: topMedicinesLimit, daysBack: salesTrendDays);
    final reorderEstimates = getReorderEstimates(
      targetStockDays: targetStockDays,
      criticalThreshold: criticalThreshold,
    );
    final recentTransactions = getRecentTransactions(count: transactionsCount);
    
    // Calculate totals for the period
    double totalRevenue = 0;
    int totalUnitsSold = 0;
    int totalTransactions = 0;
    
    for (final entry in salesTrend.values) {
      totalRevenue += entry['revenue'] as double;
      totalUnitsSold += entry['unitsSold'] as int;
      totalTransactions += entry['transactions'] as int;
    }
    
    return {
      'salesTrend': salesTrend,
      'topMedicines': topMedicines,
      'reorderEstimates': reorderEstimates,
      'recentTransactions': recentTransactions,
      'summary': {
        'totalRevenue': totalRevenue,
        'totalUnitsSold': totalUnitsSold,
        'totalTransactions': totalTransactions,
        'periodDays': salesTrendDays,
        'minimumStockDays': targetStockDays,
      },
    };
  }
}
