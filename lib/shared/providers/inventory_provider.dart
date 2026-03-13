import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';
import '../models/medicine.dart';
import '../models/purchase_record.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import 'dart:io';
import '../services/local_server_service.dart';
import '../../objectbox.g.dart';

class InventoryProvider extends ChangeNotifier {
  final Box<Medicine> _box = ObjectBoxService.instance.medicineBox;
  final Box<PurchaseRecord> _purchaseBox =
      ObjectBoxService.instance.purchaseBox;
  final Box<MedicineBatch> _batchBox = ObjectBoxService.instance.batchBox;

  List<Medicine> _medicines = [];
  List<PurchaseRecord> _purchaseHistory = [];
  String _searchQuery = '';
  String _filterWarehouse = 'all'; // all, low-stock, main-empty
  String _sortBy = 'name'; // name, price, stock

  String get sortBy => _sortBy;
  String get filterWarehouse => _filterWarehouse;

  List<Medicine> get medicines => _filtered();
  List<PurchaseRecord> get purchaseHistory =>
      List.unmodifiable(_purchaseHistory);
  int get lowStockCount => _medicines.where((m) => m.isLowStock).length;
  double get totalInventoryValue =>
      _medicines.fold(0, (sum, m) => sum + (m.storeStock * m.sellingPrice));

  List<Medicine> _filtered() {
    var list = _medicines.where((m) {
      final matchesQuery = _searchQuery.isEmpty ||
          m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.barcode.contains(_searchQuery);
      final matchesFilter = _filterWarehouse == 'all' ||
          (_filterWarehouse == 'low-stock' && m.isLowStock) ||
          (_filterWarehouse == 'main-empty' && m.mainStock == 0);
      return matchesQuery && matchesFilter;
    }).toList();

    if (_sortBy == 'name') {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_sortBy == 'price') {
      list.sort((a, b) =>
          b.sellingPrice.compareTo(a.sellingPrice)); // Highest price first
    } else if (_sortBy == 'stock') {
      list.sort((a, b) => (a.mainStock + a.storeStock)
          .compareTo(b.mainStock + b.storeStock)); // Lowest config first
    }
    return list;
  }

  Medicine? findByBarcode(String barcode) {
    try {
      return _medicines.firstWhere((m) => m.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  void load() {
    _medicines = _box.getAll();
    _purchaseHistory = _purchaseBox.getAll();
    _purchaseHistory.sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    notifyListeners();
  }

  void setSearch(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setFilter(String f) {
    _filterWarehouse = f;
    notifyListeners();
  }

  void setSort(String s) {
    _sortBy = s;
    notifyListeners();
  }

  void addMedicine(Medicine m, {SyncService? syncService}) {
    m.updatedAt = DateTime.now();
    _box.put(m);
    load();

    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushMedicine(m);
    }
  }

  void updateMedicine(Medicine m, {SyncService? syncService}) {
    m.updatedAt = DateTime.now();
    _box.put(m);
    load();

    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushMedicine(m);
    }
  }

  void deleteMedicine(int id, {SyncService? syncService}) {
    _box.remove(id);
    load();

    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      syncService.pushMedicineDelete(id);
    }
  }

  // Called after a sale checkout to deduct storeStock using FIFO (soonest expiry first)
  void deductStoreStock(int medicineId, int qty) {
    final m = _box.get(medicineId);
    if (m != null) {
      int remainingToDeduct = qty;

      // Get batches sorted by expiry date
      final batches = m.batches.toList();
      batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

      for (var batch in batches) {
        if (remainingToDeduct <= 0) break;

        if (batch.storeStock > 0) {
          final deduction = remainingToDeduct > batch.storeStock
              ? batch.storeStock
              : remainingToDeduct;

          batch.storeStock -= deduction;
          remainingToDeduct -= deduction;
          _batchBox.put(batch);
        }
      }

      // Update the main medicine entity's cached stock
      m.storeStock = (m.storeStock - qty).clamp(0, 999999);
      m.updatedAt = DateTime.now();
      _box.put(m);
      load();

      if (Platform.isWindows) {
        if (LocalServerService.instance.isRunning) {
          LocalServerService.instance.broadcast({'event': 'medicines_updated'});
        }
      }
    }
  }

  // Called after warehouse transfer
  void applyTransfer({
    required int medicineId,
    required int qty,
    required String from,
    required String to,
    String? batchNo, // Optional: specify a batch
    SyncService? syncService,
  }) {
    final m = _box.get(medicineId);
    if (m != null) {
      int remaining = qty;
      final batches = m.batches.toList();

      if (batchNo != null) {
        // Transfer from a specific batch if specified
        final batch = batches.where((b) => b.batchNo == batchNo).firstOrNull;
        if (batch != null) {
          _transferInBatch(batch, qty, from, to);
          remaining = 0;
        }
      } else {
        // Fallback: Use soonest expiry for store transfers, or just any for warehouse
        batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
        for (var batch in batches) {
          if (remaining <= 0) break;

          int available = (from == 'main') ? batch.mainStock : batch.storeStock;
          if (available > 0) {
            final move = remaining > available ? available : remaining;
            _transferInBatch(batch, move, from, to);
            remaining -= move;
          }
        }
      }

      if (from == 'main' && to == 'store') {
        m.mainStock = (m.mainStock - qty).clamp(0, 999999);
        m.storeStock += qty;
      } else if (from == 'store' && to == 'main') {
        m.storeStock = (m.storeStock - qty).clamp(0, 999999);
        m.mainStock += qty;
      }
      m.updatedAt = DateTime.now();
      _box.put(m);
      load();

      if (Platform.isAndroid && syncService != null) {
        syncService.pushMedicine(m);
      }
    }
  }

  void _transferInBatch(
      MedicineBatch batch, int qty, String from, String to) {
    if (from == 'main' && to == 'store') {
      batch.mainStock = (batch.mainStock - qty).clamp(0, 999999);
      batch.storeStock += qty;
    } else if (from == 'store' && to == 'main') {
      batch.storeStock = (batch.storeStock - qty).clamp(0, 999999);
      batch.mainStock += qty;
    }
    _batchBox.put(batch);
  }

  /// Bulk update mainStock for multiple medicines with optional batch info
  void addBatchStock(
    Map<int, int> mainUpdates, {
    Map<int, int> storeUpdates = const {},
    String batchNo = '',
    DateTime? expiryDate,
    String note = '',
    String supplier = '',
    SyncService? syncService,
  }) {
    final ids = {...mainUpdates.keys, ...storeUpdates.keys}.toList();
    final medicinesToUpdate = _box.getMany(ids);
    final List<Medicine> finalUpdates = [];
    final List<PurchaseRecord> purchaseRecords = [];
    final now = DateTime.now();

    for (var m in medicinesToUpdate) {
      if (m != null) {
        final mainQty = mainUpdates[m.id] ?? 0;
        final storeQty = storeUpdates[m.id] ?? 0;
        if (mainQty <= 0 && storeQty <= 0) continue;

        // Update or create batch
        if (batchNo.isNotEmpty && expiryDate != null) {
          var batch = m.batches.where((b) => b.batchNo == batchNo).firstOrNull;
          if (batch == null) {
            batch = MedicineBatch(
              batchNo: batchNo,
              expiryDate: expiryDate,
              mainStock: mainQty,
              storeStock: storeQty,
            );
            batch.medicine.target = m;
            m.batches.add(batch);
          } else {
            batch.mainStock += mainQty;
            batch.storeStock += storeQty;
            _batchBox.put(batch);
          }
        }

        m.mainStock += mainQty;
        m.storeStock += storeQty;
        m.updatedAt = now;
        finalUpdates.add(m);

        // Create history record
        purchaseRecords.add(PurchaseRecord(
          medicineId: m.id,
          medicineName: m.name,
          qty: mainQty + storeQty,
          purchasePrice: m.purchasePrice,
          purchasedAt: now,
          note: note,
          supplier: supplier,
        ));

        if (Platform.isAndroid && syncService != null) {
          syncService.pushMedicine(m);
        }
      }
    }

    if (finalUpdates.isNotEmpty) {
      _box.putMany(finalUpdates);
      _purchaseBox.putMany(purchaseRecords);
      load();

      if (Platform.isWindows && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    }
  }

  void updatePurchase(PurchaseRecord p, int newQty,
      {SyncService? syncService}) {
    final m = _box.get(p.medicineId);
    if (m != null) {
      // Adjust stock by the difference
      final diff = newQty - p.qty;
      m.mainStock += diff;
      m.updatedAt = DateTime.now();
      _box.put(m);

      // Update purchase record
      p.qty = newQty;
      _purchaseBox.put(p);
      load();

      if (Platform.isWindows && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
      if (Platform.isAndroid && syncService != null) {
        syncService.pushMedicine(m);
      }
    }
  }

  void deletePurchase(PurchaseRecord p, {SyncService? syncService}) {
    final m = _box.get(p.medicineId);
    if (m != null) {
      // Revert stock
      m.mainStock = (m.mainStock - p.qty).clamp(0, 999999);
      m.updatedAt = DateTime.now();
      _box.put(m);

      _purchaseBox.remove(p.id);
      load();

      if (Platform.isWindows && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
      if (Platform.isAndroid && syncService != null) {
        syncService.pushMedicine(m);
      }
    }
  }

  void deleteBatch(Medicine m, MedicineBatch batch, {SyncService? syncService}) {
    // 1. Revert medicine's aggregate stock
    m.mainStock = (m.mainStock - batch.mainStock).clamp(0, 999999);
    m.storeStock = (m.storeStock - batch.storeStock).clamp(0, 999999);
    m.updatedAt = DateTime.now();
    
    // 2. Remove batch from medicine's ToMany (ObjectBox handles this but we need to put m)
    m.batches.removeWhere((b) => b.id == batch.id);
    _box.put(m);

    // 3. Delete the batch entity itself
    _batchBox.remove(batch.id);

    load();

    if (Platform.isWindows && LocalServerService.instance.isRunning) {
      LocalServerService.instance.broadcast({'event': 'medicines_updated'});
    }
    if (Platform.isAndroid && syncService != null) {
      syncService.pushMedicine(m);
    }
  }

  List<Map<String, dynamic>> toSyncJson() => _medicines
      .map((m) => {
            'id': m.id,
            'name': m.name,
            'barcode': m.barcode,
            'category': m.category,
            'unit': m.unit,
            'purchasePrice': m.purchasePrice,
            'sellingPrice': m.sellingPrice,
            'mainStock': m.mainStock,
            'storeStock': m.storeStock,
            'lowStockThreshold': m.lowStockThreshold,
            'updatedAt': m.updatedAt.toIso8601String(),
          })
      .toList();
}
