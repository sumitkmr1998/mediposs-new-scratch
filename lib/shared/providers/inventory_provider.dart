import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';
import '../models/medicine.dart';
import '../models/purchase_record.dart';
import '../models/restock_request.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import 'dart:io';
import '../services/local_server_service.dart';
import '../../objectbox.g.dart';

class InventoryProvider extends ChangeNotifier {
  final Box<Medicine> _box = ObjectBoxService.instance.medicineBox;
  final Box<PurchaseRecord> _purchaseBox =
      ObjectBoxService.instance.purchaseBox;
  final Box<MedicineBatch> _batchBox = ObjectBoxService.instance.batchBox;
  final Box<RestockRequest> _restockBox = ObjectBoxService.instance.restockRequestBox;

  List<Medicine> _medicines = [];
  List<PurchaseRecord> _purchaseHistory = [];
  String _searchQuery = '';
  String _filterWarehouse = 'all'; // all, low-stock, main-empty
  String _sortBy = 'name'; // name, price, stock

  String get sortBy => _sortBy;
  String get filterWarehouse => _filterWarehouse;

  List<Medicine> get medicines => _filtered();
  List<Medicine> get rawMedicines => List.unmodifiable(_medicines);
  List<PurchaseRecord> get purchaseHistory =>
      List.unmodifiable(_purchaseHistory);
  int get lowStockCount => _medicines.where((m) => m.isLowStock).length;
  List<Medicine> get lowStockMedicines => _medicines.where((m) => m.isLowStock).toList();
  
  int get expiredCount => expiredMedicines.length;
  int get nearExpiryCount => nearExpiryMedicines.length;
  int get totalMedicinesCount => _medicines.length;

  List<Medicine> get expiredMedicines {
    final now = DateTime.now();
    return _medicines.where((m) => m.batches.any((b) => 
      b.expiryDate.isBefore(now) && (b.mainStock > 0 || b.storeStock > 0)
    )).toList();
  }

  List<Medicine> get nearExpiryMedicines {
    final now = DateTime.now();
    final thresholdDays = ObjectBoxService.instance.settings.nearExpiryThresholdDays;
    final threshold = now.add(Duration(days: thresholdDays));
    return _medicines.where((m) => m.batches.any((b) => 
      b.expiryDate.isAfter(now) && 
      b.expiryDate.isBefore(threshold) && 
      (b.mainStock > 0 || b.storeStock > 0)
    )).toList();
  }

  double get totalInventoryValue =>
      _medicines.fold(0, (sum, m) => sum + (m.storeStock * m.sellingPrice));

  /// Reconciles cached aggregate stock with batch-level stock for all medicines.
  void reconcileAllStock() {
    for (final m in _medicines) {
      m.recalculateStockFromBatches();
      _box.put(m);
    }
    load();
  }

  List<Medicine> _filtered() {
    var list = _medicines.where((m) {
      final matchesQuery = _searchQuery.isEmpty ||
          m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.barcode.contains(_searchQuery);
      final matchesFilter = _filterWarehouse == 'all' ||
          (_filterWarehouse == 'low-stock' && m.isLowStock) ||
          (_filterWarehouse == 'main-empty' && m.mainStock == 0) ||
          (_filterWarehouse == 'expired' &&
              m.batches.any((b) =>
                  b.expiryDate.isBefore(DateTime.now()) &&
                  (b.mainStock > 0 || b.storeStock > 0))) ||
          (_filterWarehouse == 'near-expiry' &&
              m.batches.any((b) =>
                  b.expiryDate.isAfter(DateTime.now()) &&
                  b.expiryDate.isBefore(DateTime.now().add(Duration(
                      days: ObjectBoxService.instance.settings
                          .nearExpiryThresholdDays))) &&
                  (b.mainStock > 0 || b.storeStock > 0)));
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
    m.name = m.name.trim();
    m.barcode = m.barcode.trim();
    m.updatedAt = DateTime.now();
    _box.put(m);
    load();

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'medicine',
        action: 'create',
        data: m.toJson(),
      );
    }
  }

  void updateMedicine(Medicine m, {SyncService? syncService}) {
    m.name = m.name.trim();
    m.barcode = m.barcode.trim();
    m.updatedAt = DateTime.now();
    _box.put(m);
    load();

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'medicine',
        action: 'update',
        data: m.toJson(),
      );
    }
  }

  void deleteMedicine(int id, {SyncService? syncService}) {
    final m = _box.get(id);
    if (m == null) return;
    final barcode = m.barcode;
    final name = m.name;

    _box.remove(id);
    load();

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({
          'event': 'medicine_deleted',
          'barcode': barcode,
          'name': name,
        });
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'medicine',
        action: 'delete',
        data: {'barcode': barcode, 'name': name},
      );
    }
  }

  // Called after a sale checkout to deduct storeStock using FIFO (soonest expiry first)
  // Or called after a return to restock (negative qty)
  List<DeductedBatch> deductStoreStock(int medicineId, int qty) {
    final m = _box.get(medicineId);
    final deducted = <DeductedBatch>[];
    if (m != null) {
      if (qty > 0) {
        // DEDUCTION (Sale) - Use FIFO (soonest expiry first)
        int remainingToDeduct = qty;
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

            deducted.add(DeductedBatch(
              batchNo: batch.batchNo,
              expiryDate: batch.expiryDate,
              qty: deduction,
            ));
          }
        }

        if (remainingToDeduct > 0) {
          deducted.add(DeductedBatch(
            batchNo: 'N/A',
            expiryDate: DateTime.now(),
            qty: remainingToDeduct,
          ));
        }
      } else if (qty < 0) {
        // RESTOCKING (Return) - Add back to the latest batch (furthest expiry)
        int qToRestore = qty.abs();
        final batches = m.batches.toList();
        if (batches.isNotEmpty) {
          // Sort furthest expiry first
          batches.sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
          final latestBatch = batches.first;
          latestBatch.storeStock += qToRestore;
          _batchBox.put(latestBatch);

          deducted.add(DeductedBatch(
            batchNo: latestBatch.batchNo,
            expiryDate: latestBatch.expiryDate,
            qty: qty, // negative
          ));
        } else {
          deducted.add(DeductedBatch(
            batchNo: 'N/A',
            expiryDate: DateTime.now(),
            qty: qty, // negative
          ));
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
    return deducted;
  }

  // Called after a clinical dispense checkout to deduct mainStock using FIFO (soonest expiry first)
  // Or called after a return to restock (negative qty)
  List<DeductedBatch> deductClinicStock(int medicineId, int qty) {
    final m = _box.get(medicineId);
    final deducted = <DeductedBatch>[];
    if (m != null) {
      if (qty > 0) {
        // DEDUCTION (Sale) - Use FIFO (soonest expiry first)
        int remainingToDeduct = qty;
        final batches = m.batches.toList();
        batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

        for (var batch in batches) {
          if (remainingToDeduct <= 0) break;

          if (batch.mainStock > 0) {
            final deduction = remainingToDeduct > batch.mainStock
                ? batch.mainStock
                : remainingToDeduct;

            batch.mainStock -= deduction;
            remainingToDeduct -= deduction;
            _batchBox.put(batch);

            deducted.add(DeductedBatch(
              batchNo: batch.batchNo,
              expiryDate: batch.expiryDate,
              qty: deduction,
            ));
          }
        }

        if (remainingToDeduct > 0) {
          deducted.add(DeductedBatch(
            batchNo: 'N/A',
            expiryDate: DateTime.now(),
            qty: remainingToDeduct,
          ));
        }
        
        m.recalculateStockFromBatches();
        
        // Automated Restock Request Logic
        final threshold = ObjectBoxService.instance.settings.lowStockThreshold;
        if (m.mainStock < threshold) {
          // Check if there is already a PENDING request
          final existingRequests = _restockBox.query(RestockRequest_.medicineId.equals(m.id).and(RestockRequest_.status.equals('PENDING'))).build().find();
          if (existingRequests.isEmpty) {
            // Suggest restocking up to some comfortable level above threshold or just a standard batch size
            // For now, let's request threshold * 2 or something, or just threshold. Let's ask for the threshold quantity.
            final requestQty = threshold > 0 ? threshold * 2 : 50; 
            _restockBox.put(RestockRequest(
              medicineId: m.id,
              medicineName: m.name,
              requestedQty: requestQty,
              requestedAt: DateTime.now(),
              notes: 'Automated request due to low clinic stock (${m.mainStock} < $threshold)',
            ));
          }
        }
      } else if (qty < 0) {
        // RESTOCKING (Return) - Add back to the latest batch (furthest expiry)
        int qToRestore = qty.abs();
        final batches = m.batches.toList();
        if (batches.isNotEmpty) {
          // Sort furthest expiry first
          batches.sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
          final latestBatch = batches.first;
          latestBatch.mainStock += qToRestore;
          _batchBox.put(latestBatch);

          deducted.add(DeductedBatch(
            batchNo: latestBatch.batchNo,
            expiryDate: latestBatch.expiryDate,
            qty: qty, // negative
          ));
        } else {
          deducted.add(DeductedBatch(
            batchNo: 'N/A',
            expiryDate: DateTime.now(),
            qty: qty, // negative
          ));
        }
      }

      // Update the main medicine entity's cached stock
      m.mainStock = (m.mainStock - qty).clamp(0, 999999);
      m.updatedAt = DateTime.now();
      _box.put(m);
      load();

      if (Platform.isWindows) {
        if (LocalServerService.instance.isRunning) {
          LocalServerService.instance.broadcast({'event': 'medicines_updated'});
        }
      }
    }
    return deducted;
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

          int available = 0;
          if (from == 'main') available = batch.mainStock;
          else if (from == 'store') available = batch.storeStock;
          else if (from == 'bulkClinic') available = batch.bulkClinicStock;
          else if (from == 'bulkStore') available = batch.bulkStoreStock;

          if (available > 0) {
            final move = remaining > available ? available : remaining;
            _transferInBatch(batch, move, from, to);
            remaining -= move;
          }
        }
      }

      int getStock(String loc) {
        if (loc == 'main') return m.mainStock;
        if (loc == 'store') return m.storeStock;
        if (loc == 'bulkClinic') return m.bulkClinicStock;
        if (loc == 'bulkStore') return m.bulkStoreStock;
        return 0;
      }
      void setStock(String loc, int val) {
        if (loc == 'main') m.mainStock = val;
        if (loc == 'store') m.storeStock = val;
        if (loc == 'bulkClinic') m.bulkClinicStock = val;
        if (loc == 'bulkStore') m.bulkStoreStock = val;
      }

      setStock(from, (getStock(from) - qty).clamp(0, 999999));
      setStock(to, getStock(to) + qty);

      m.updatedAt = DateTime.now();
      _box.put(m);
      load();
      final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      } else if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'medicine',
          action: 'update',
          data: m.toJson(),
        );
      }
    }
  }

  void _transferInBatch(
      MedicineBatch batch, int qty, String from, String to) {
    int getStock(String loc) {
      if (loc == 'main') return batch.mainStock;
      if (loc == 'store') return batch.storeStock;
      if (loc == 'bulkClinic') return batch.bulkClinicStock;
      if (loc == 'bulkStore') return batch.bulkStoreStock;
      return 0;
    }
    void setStock(String loc, int val) {
      if (loc == 'main') batch.mainStock = val;
      if (loc == 'store') batch.storeStock = val;
      if (loc == 'bulkClinic') batch.bulkClinicStock = val;
      if (loc == 'bulkStore') batch.bulkStoreStock = val;
    }

    setStock(from, (getStock(from) - qty).clamp(0, 999999));
    setStock(to, getStock(to) + qty);

    _batchBox.put(batch);
  }

  /// Bulk update mainStock for multiple medicines with optional batch info
  void addBatchStock(
    Map<int, int> mainUpdates, {
    Map<int, int> storeUpdates = const {},
    Map<int, int> bulkClinicUpdates = const {},
    Map<int, int> bulkStoreUpdates = const {},
    String batchNo = '',
    DateTime? expiryDate,
    String note = '',
    String supplier = '',
    SyncService? syncService,
  }) {
    final ids = {
      ...mainUpdates.keys,
      ...storeUpdates.keys,
      ...bulkClinicUpdates.keys,
      ...bulkStoreUpdates.keys
    }.toList();
    final medicinesToUpdate = _box.getMany(ids);
    final List<Medicine> finalUpdates = [];
    final List<PurchaseRecord> purchaseRecords = [];
    final now = DateTime.now();

    for (var m in medicinesToUpdate) {
      if (m != null) {
        final mainQty = mainUpdates[m.id] ?? 0;
        final storeQty = storeUpdates[m.id] ?? 0;
        final bulkClinicQty = bulkClinicUpdates[m.id] ?? 0;
        final bulkStoreQty = bulkStoreUpdates[m.id] ?? 0;
        if (mainQty <= 0 && storeQty <= 0 && bulkClinicQty <= 0 && bulkStoreQty <= 0) continue;

        // Update or create batch
        if (batchNo.isNotEmpty && expiryDate != null) {
          var batch = m.batches.where((b) => b.batchNo == batchNo).firstOrNull;
          if (batch == null) {
            batch = MedicineBatch(
              batchNo: batchNo,
              expiryDate: expiryDate,
              mainStock: mainQty,
              storeStock: storeQty,
              bulkClinicStock: bulkClinicQty,
              bulkStoreStock: bulkStoreQty,
            );
            batch.medicine.target = m;
            m.batches.add(batch);
          } else {
            batch.mainStock += mainQty;
            batch.storeStock += storeQty;
            batch.bulkClinicStock += bulkClinicQty;
            batch.bulkStoreStock += bulkStoreQty;
            _batchBox.put(batch);
          }
        }

        m.mainStock += mainQty;
        m.storeStock += storeQty;
        m.bulkClinicStock += bulkClinicQty;
        m.bulkStoreStock += bulkStoreQty;
        m.updatedAt = now;
        finalUpdates.add(m);

        // Create history record
        purchaseRecords.add(PurchaseRecord(
          medicineId: m.id,
          medicineName: m.name,
          qty: mainQty + storeQty + bulkClinicQty + bulkStoreQty,
          purchasePrice: m.purchasePrice,
          purchasedAt: now,
          note: note,
          supplier: supplier,
        ));

        final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
        if (isClient) {
          SyncQueueService.instance.addToQueue(
            entity: 'medicine',
            action: 'update',
            data: m.toJson(),
          );
        }
      }
    }

    if (finalUpdates.isNotEmpty) {
      _box.putMany(finalUpdates);
      _purchaseBox.putMany(purchaseRecords);
      load();

      final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
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

      // Also try to adjust a batch to keep them in sync
      if (m.batches.isNotEmpty) {
        final latest = m.batches.toList()..sort((a,b) => b.id.compareTo(a.id));
        final batch = latest.first;
        batch.mainStock += diff;
        _batchBox.put(batch);
      }

      _box.put(m);

      // Update purchase record
      p.qty = newQty;
      _purchaseBox.put(p);
      load();

      final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
      if (isClient && syncService != null) {
        syncService.pushMedicine(m);
      }
    }
  }

  void deletePurchase(PurchaseRecord p, {SyncService? syncService}) {
    final m = _box.get(p.medicineId);
    if (m != null) {
      // Revert stock
      final diff = -p.qty;
      m.mainStock = (m.mainStock + diff).clamp(0, 999999);
      m.updatedAt = DateTime.now();

      // Also adjust batch
      if (m.batches.isNotEmpty) {
        final latest = m.batches.toList()..sort((a,b) => b.id.compareTo(a.id));
        final batch = latest.first;
        batch.mainStock = (batch.mainStock + diff).clamp(0, 999999);
        _batchBox.put(batch);
      }

      _box.put(m);

      _purchaseBox.remove(p.id);
      load();

      final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
      if (isClient && syncService != null) {
        syncService.pushMedicine(m);
      }
    }
  }

  void deleteBatch(Medicine m, MedicineBatch batch, {SyncService? syncService}) {
    // 1. Revert medicine's aggregate stock
    m.mainStock = (m.mainStock - batch.mainStock).clamp(0, 999999);
    m.storeStock = (m.storeStock - batch.storeStock).clamp(0, 999999);
    m.bulkClinicStock = (m.bulkClinicStock - batch.bulkClinicStock).clamp(0, 999999);
    m.bulkStoreStock = (m.bulkStoreStock - batch.bulkStoreStock).clamp(0, 999999);
    m.updatedAt = DateTime.now();
    
    // 2. Remove batch from medicine's ToMany (ObjectBox handles this but we need to put m)
    m.batches.removeWhere((b) => b.id == batch.id);
    _box.put(m);

    // 3. Delete the batch entity itself
    _batchBox.remove(batch.id);

    load();

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub && LocalServerService.instance.isRunning) {
      LocalServerService.instance.broadcast({'event': 'medicines_updated'});
    }
    if (isClient && syncService != null) {
      syncService.pushMedicine(m);
    }
  }

  void updateBatchDetail(Medicine m, MedicineBatch batch, {
    required String batchNo,
    required DateTime expiryDate,
    required int mainStock,
    required int storeStock,
    int bulkClinicStock = 0,
    int bulkStoreStock = 0,
    SyncService? syncService,
  }) {
    batch.batchNo = batchNo;
    batch.expiryDate = expiryDate;
    batch.mainStock = mainStock.clamp(0, 999999);
    batch.storeStock = storeStock.clamp(0, 999999);
    batch.bulkClinicStock = bulkClinicStock.clamp(0, 999999);
    batch.bulkStoreStock = bulkStoreStock.clamp(0, 999999);
    
    _batchBox.put(batch);
    
    // Core Fix: Recalculate medicine totals now that batch has changed
    m.recalculateStockFromBatches();
    _box.put(m);
    
    load();

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub && LocalServerService.instance.isRunning) {
      LocalServerService.instance.broadcast({'event': 'medicines_updated'});
    }
    if (isClient && syncService != null) {
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
            'bulkClinicStock': m.bulkClinicStock,
            'bulkStoreStock': m.bulkStoreStock,
            'lowStockThreshold': m.lowStockThreshold,
            'updatedAt': m.updatedAt.toIso8601String(),
          })
      .toList();
}

class DeductedBatch {
  final String batchNo;
  final DateTime expiryDate;
  final int qty;

  DeductedBatch({
    required this.batchNo,
    required this.expiryDate,
    required this.qty,
  });
}
