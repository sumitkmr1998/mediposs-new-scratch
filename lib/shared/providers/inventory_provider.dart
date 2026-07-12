import 'package:flutter/foundation.dart';
import '../models/medicine.dart';
import '../models/purchase_record.dart';
import '../models/restock_request.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/audit_service.dart';
import 'dart:io';
import '../services/local_server_service.dart';
import '../utils/analytics_helper.dart';
import '../models/sale.dart';
import '../../objectbox.g.dart';

class InventoryProvider extends ChangeNotifier {
  final Box<Medicine> _box = ObjectBoxService.instance.medicineBox;
  final Box<PurchaseRecord> _purchaseBox =
      ObjectBoxService.instance.purchaseBox;
  final Box<MedicineBatch> _batchBox = ObjectBoxService.instance.batchBox;
  final Box<RestockRequest> _restockBox =
      ObjectBoxService.instance.restockRequestBox;

  List<Medicine> _medicines = [];
  List<PurchaseRecord> _purchaseHistory = [];
  String _searchQuery = '';
  String _filterWarehouse = 'all'; // all, low-stock, main-empty
  String _sortBy = 'name'; // name, price, stock

  String get sortBy => _sortBy;
  String get filterWarehouse => _filterWarehouse;
  String get searchQuery => _searchQuery;

  List<Medicine> get medicines => _filtered();
  List<Medicine> get rawMedicines => List.unmodifiable(_medicines);
  List<PurchaseRecord> get purchaseHistory =>
      List.unmodifiable(_purchaseHistory);
  int get lowStockCount => _medicines.where((m) => m.isLowStock).length;
  List<Medicine> get lowStockMedicines =>
      _medicines.where((m) => m.isLowStock).toList();

  bool isSmartLowStock(Medicine m, List<Sale> sales) {
    if (m.totalStock <= 0) return true;
    final daily = AnalyticsHelper.dailyConsumptionRate(m.id, sales, trendDays: 30);
    if (daily > 0) {
      final daysLeft = m.totalStock / daily;
      return daysLeft < 30;
    }
    return m.isLowStock;
  }

  int getSmartLowStockCount(List<Sale> sales) {
    return _medicines.where((m) => isSmartLowStock(m, sales)).length;
  }

  List<Medicine> getSmartLowStockMedicines(List<Sale> sales) {
    return _medicines.where((m) => isSmartLowStock(m, sales)).toList();
  }

  int get expiredCount => expiredMedicines.length;
  int get nearExpiryCount => nearExpiryMedicines.length;
  int get totalMedicinesCount => _medicines.length;

  List<Medicine> get expiredMedicines {
    final now = DateTime.now();
    return _medicines
        .where((m) => m.batches.any((b) =>
            b.expiryDate.isBefore(now) &&
            (b.mainStock > 0 || b.storeStock > 0)))
        .toList();
  }

  List<Medicine> get nearExpiryMedicines {
    final now = DateTime.now();
    final thresholdDays =
        ObjectBoxService.instance.settings.nearExpiryThresholdDays;
    final threshold = now.add(Duration(days: thresholdDays));
    return _medicines
        .where((m) => m.batches.any((b) =>
            b.expiryDate.isAfter(now) &&
            b.expiryDate.isBefore(threshold) &&
            (b.mainStock > 0 || b.storeStock > 0)))
        .toList();
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

  List<Medicine> getFilteredMedicines(List<Sale> sales) {
    var list = _medicines.where((m) {
      final matchesQuery = _searchQuery.isEmpty ||
          m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.barcode.contains(_searchQuery);
      final matchesFilter = _filterWarehouse == 'all' ||
          (_filterWarehouse == 'low-stock' && isSmartLowStock(m, sales)) ||
          (_filterWarehouse == 'main-empty' && m.mainStock == 0) ||
          (_filterWarehouse == 'expired' &&
              m.batches.any((b) =>
                  b.expiryDate.isBefore(DateTime.now()) &&
                  (b.mainStock > 0 || b.storeStock > 0))) ||
          (_filterWarehouse == 'near-expiry' &&
              m.batches.any((b) =>
                  b.expiryDate.isAfter(DateTime.now()) &&
                  b.expiryDate.isBefore(DateTime.now().add(Duration(
                      days: ObjectBoxService
                          .instance.settings.nearExpiryThresholdDays))) &&
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
                      days: ObjectBoxService
                          .instance.settings.nearExpiryThresholdDays))) &&
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

  void addMedicine(Medicine m, {SyncService? syncService, AppUser? actor}) {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' || actor.canEditInventory)) {
      throw Exception('Unauthorized: You do not have permission to add new medicines.');
    }
    m.name = m.name.trim();
    m.barcode = m.barcode.trim();
    m.updatedAt = DateTime.now();
    _box.put(m);

    // Log medicine creation
    AuditService.instance.log(
      action: 'CREATE',
      entityType: 'Medicine',
      entityId: m.id.toString(),
      description: 'Added new medicine: ${m.name} (Barcode: ${m.barcode})',
      details: m.toJson(),
      actor: actor,
    );

    load();

    final isClient = Platform.isAndroid ||
        (Platform.isWindows &&
            ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows &&
        !ObjectBoxService.instance.settings.isWindowsClient;
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

  void updateMedicine(Medicine m, {SyncService? syncService, AppUser? actor}) {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' || actor.canEditInventory)) {
      throw Exception('Unauthorized: You do not have permission to update medicines.');
    }
    m.name = m.name.trim();
    m.barcode = m.barcode.trim();
    m.updatedAt = DateTime.now();

    final oldMed = _box.get(m.id);
    final oldJson = oldMed != null ? oldMed.toJson() : <String, dynamic>{};

    _box.put(m);

    // Log medicine update
    AuditService.instance.log(
      action: 'UPDATE',
      entityType: 'Medicine',
      entityId: m.id.toString(),
      description: 'Updated medicine details: ${m.name} (Barcode: ${m.barcode})',
      details: {
        'before': oldJson,
        'after': m.toJson(),
      },
      actor: actor,
    );

    load();

    final isClient = Platform.isAndroid ||
        (Platform.isWindows &&
            ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows &&
        !ObjectBoxService.instance.settings.isWindowsClient;
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

  void deleteMedicine(int id, {SyncService? syncService, AppUser? actor}) {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' || actor.canDeleteInventory)) {
      throw Exception('Unauthorized: You do not have permission to delete medicines.');
    }
    final m = _box.get(id);
    if (m == null) return;
    final barcode = m.barcode;
    final name = m.name;

    _box.remove(id);

    // Log medicine deletion
    AuditService.instance.log(
      action: 'DELETE',
      entityType: 'Medicine',
      entityId: id.toString(),
      description: 'Deleted medicine: $name (Barcode: $barcode)',
      details: {'id': id, 'name': name, 'barcode': barcode},
      actor: actor,
    );

    load();

    final isClient = Platform.isAndroid ||
        (Platform.isWindows &&
            ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows &&
        !ObjectBoxService.instance.settings.isWindowsClient;
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
    if (medicineId <= 0) return [];
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
          if (batch.expiryDate.isBefore(DateTime.now())) continue;

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
      m.recalculateStockFromBatches();
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
    if (medicineId <= 0) return [];
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
          if (batch.expiryDate.isBefore(DateTime.now())) continue;

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
          final existingRequests = _restockBox
              .query(RestockRequest_.medicineId
                  .equals(m.id)
                  .and(RestockRequest_.status.equals('PENDING')))
              .build()
              .find();
          if (existingRequests.isEmpty) {
            // Suggest restocking up to some comfortable level above threshold or just a standard batch size
            // For now, let's request threshold * 2 or something, or just threshold. Let's ask for the threshold quantity.
            final requestQty = threshold > 0 ? threshold * 2 : 50;
            _restockBox.put(RestockRequest(
              medicineId: m.id,
              medicineName: m.name,
              requestedQty: requestQty,
              requestedAt: DateTime.now(),
              notes:
                  'Automated request due to low clinic stock (${m.mainStock} < $threshold)',
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
    AppUser? actor,
  }) {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' || actor.canTransferStock)) {
      throw Exception('Unauthorized: You do not have permission to execute stock transfers.');
    }

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
          if (from == 'main' || from == 'clinic') {
            available = batch.mainStock;
          } else if (from == 'store')
            available = batch.storeStock;
          else if (from == 'bulkClinic')
            available = batch.bulkClinicStock;
          else if (from == 'bulkStore') available = batch.bulkStoreStock;

          if (available > 0) {
            final move = remaining > available ? available : remaining;
            _transferInBatch(batch, move, from, to);
            remaining -= move;
          }
        }
      }

      m.recalculateStockFromBatches();
      _box.put(m);

      // Log stock transfer
      AuditService.instance.log(
        action: 'UPDATE',
        entityType: 'StockTransfer',
        entityId: m.id.toString(),
        description: 'Transferred $qty units of ${m.name} from $from to $to',
        details: {
          'medicineId': m.id,
          'medicineName': m.name,
          'qty': qty,
          'from': from,
          'to': to,
          'batchNo': batchNo,
        },
        actor: actor,
      );

      load();
      final isClient = Platform.isAndroid ||
          (Platform.isWindows &&
              ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows &&
          !ObjectBoxService.instance.settings.isWindowsClient;
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

  void _transferInBatch(MedicineBatch batch, int qty, String from, String to) {
    int getStock(String loc) {
      if (loc == 'main' || loc == 'clinic') return batch.mainStock;
      if (loc == 'store') return batch.storeStock;
      if (loc == 'bulkClinic') return batch.bulkClinicStock;
      if (loc == 'bulkStore') return batch.bulkStoreStock;
      return 0;
    }

    void setStock(String loc, int val) {
      if (loc == 'main' || loc == 'clinic') batch.mainStock = val;
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
    AppUser? actor,
  }) {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' ||
            actor.canOverrideStock ||
            actor.canEditInventory ||
            actor.canAddStock)) {
      throw Exception('Unauthorized: You do not have permission to modify batch stock.');
    }
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
        if (mainQty <= 0 &&
            storeQty <= 0 &&
            bulkClinicQty <= 0 &&
            bulkStoreQty <= 0) {
          continue;
        }

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

        if (batchNo.isNotEmpty && expiryDate != null) {
          m.recalculateStockFromBatches();
        } else {
          m.mainStock += mainQty;
          m.storeStock += storeQty;
          m.bulkClinicStock += bulkClinicQty;
          m.bulkStoreStock += bulkStoreQty;
        }
        m.updatedAt = now;
        finalUpdates.add(m);

        // Create history record
        if (mainQty > 0) {
          purchaseRecords.add(PurchaseRecord(
            medicineId: m.id,
            medicineName: m.name,
            qty: mainQty,
            purchasePrice: m.purchasePrice,
            purchasedAt: now,
            location: 'clinic',
            note: note,
            supplier: supplier,
          ));
        }
        if (storeQty > 0) {
          purchaseRecords.add(PurchaseRecord(
            medicineId: m.id,
            medicineName: m.name,
            qty: storeQty,
            purchasePrice: m.purchasePrice,
            purchasedAt: now,
            location: 'store',
            note: note,
            supplier: supplier,
          ));
        }
        if (bulkClinicQty > 0) {
          purchaseRecords.add(PurchaseRecord(
            medicineId: m.id,
            medicineName: m.name,
            qty: bulkClinicQty,
            purchasePrice: m.purchasePrice,
            purchasedAt: now,
            location: 'bulkClinic',
            note: note,
            supplier: supplier,
          ));
        }
        if (bulkStoreQty > 0) {
          purchaseRecords.add(PurchaseRecord(
            medicineId: m.id,
            medicineName: m.name,
            qty: bulkStoreQty,
            purchasePrice: m.purchasePrice,
            purchasedAt: now,
            location: 'bulkStore',
            note: note,
            supplier: supplier,
          ));
        }

        final isClient = Platform.isAndroid ||
            (Platform.isWindows &&
                ObjectBoxService.instance.settings.isWindowsClient);
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

      final isClient = Platform.isAndroid ||
          (Platform.isWindows &&
              ObjectBoxService.instance.settings.isWindowsClient);
      if (isClient) {
        for (final p in purchaseRecords) {
          SyncQueueService.instance.addToQueue(
            entity: 'purchase',
            action: 'create',
            data: p.toJson(),
          );
        }
      }

      // Log manual stock updates / batch additions
      for (final record in purchaseRecords) {
        AuditService.instance.log(
          action: 'UPDATE',
          entityType: 'Medicine',
          entityId: record.medicineId.toString(),
          description: 'Added stock for ${record.medicineName}: +${record.qty} units (Batch: $batchNo)',
          details: {
            'medicineId': record.medicineId,
            'medicineName': record.medicineName,
            'addedQty': record.qty,
            'batchNo': batchNo,
            'expiryDate': expiryDate?.toIso8601String(),
            'supplier': supplier,
            'note': note,
          },
          actor: actor,
        );
      }

      load();

      final isHub = Platform.isWindows &&
          !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    }
  }

  void updatePurchase(PurchaseRecord p, int newQty,
      {SyncService? syncService, AppUser? actor}) {
    final m = _box.get(p.medicineId);
    if (m != null) {
      // Adjust stock by the difference
      final diff = newQty - p.qty;
      if (p.location == 'store') {
        m.storeStock += diff;
      } else if (p.location == 'bulkClinic') {
        m.bulkClinicStock += diff;
      } else if (p.location == 'bulkStore') {
        m.bulkStoreStock += diff;
      } else {
        m.mainStock += diff;
      }
      m.updatedAt = DateTime.now();

      // Also try to adjust a batch to keep them in sync
      if (m.batches.isNotEmpty) {
        final latest = m.batches.toList()..sort((a, b) => b.id.compareTo(a.id));
        final batch = latest.first;
        if (p.location == 'store') {
          batch.storeStock += diff;
        } else if (p.location == 'bulkClinic') {
          batch.bulkClinicStock += diff;
        } else if (p.location == 'bulkStore') {
          batch.bulkStoreStock += diff;
        } else {
          batch.mainStock += diff;
        }
        _batchBox.put(batch);
      }

      _box.put(m);

      // Update purchase record
      final oldQty = p.qty;
      p.qty = newQty;
      _purchaseBox.put(p);

      // Log purchase update
      AuditService.instance.log(
        action: 'UPDATE',
        entityType: 'PurchaseRecord',
        entityId: p.id.toString(),
        description: 'Updated purchase quantity for ${p.medicineName}: $oldQty -> $newQty',
        details: {
          'medicineId': p.medicineId,
          'medicineName': p.medicineName,
          'oldQty': oldQty,
          'newQty': newQty,
          'location': p.location,
          'supplier': p.supplier,
        },
        actor: actor,
      );

      load();

      final isClient = Platform.isAndroid ||
          (Platform.isWindows &&
              ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows &&
          !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
      if (isClient && syncService != null) {
        syncService.pushMedicine(m);
      }
    }
  }

  void deletePurchase(PurchaseRecord p, {SyncService? syncService, AppUser? actor}) {
    final m = _box.get(p.medicineId);
    if (m != null) {
      // Revert stock
      final diff = -p.qty;
      if (p.location == 'store') {
        m.storeStock = (m.storeStock + diff).clamp(0, 999999);
      } else if (p.location == 'bulkClinic') {
        m.bulkClinicStock = (m.bulkClinicStock + diff).clamp(0, 999999);
      } else if (p.location == 'bulkStore') {
        m.bulkStoreStock = (m.bulkStoreStock + diff).clamp(0, 999999);
      } else {
        m.mainStock = (m.mainStock + diff).clamp(0, 999999);
      }
      m.updatedAt = DateTime.now();

      // Also adjust batch
      if (m.batches.isNotEmpty) {
        final latest = m.batches.toList()..sort((a, b) => b.id.compareTo(a.id));
        final batch = latest.first;
        if (p.location == 'store') {
          batch.storeStock = (batch.storeStock + diff).clamp(0, 999999);
        } else if (p.location == 'bulkClinic') {
          batch.bulkClinicStock = (batch.bulkClinicStock + diff).clamp(0, 999999);
        } else if (p.location == 'bulkStore') {
          batch.bulkStoreStock = (batch.bulkStoreStock + diff).clamp(0, 999999);
        } else {
          batch.mainStock = (batch.mainStock + diff).clamp(0, 999999);
        }
        _batchBox.put(batch);
      }

      _box.put(m);

      _purchaseBox.remove(p.id);

      // Log purchase deletion
      AuditService.instance.log(
        action: 'DELETE',
        entityType: 'PurchaseRecord',
        entityId: p.id.toString(),
        description: 'Deleted purchase record for ${p.medicineName} (-${p.qty} units)',
        details: {
          'medicineId': p.medicineId,
          'medicineName': p.medicineName,
          'qty': p.qty,
          'location': p.location,
          'supplier': p.supplier,
        },
        actor: actor,
      );

      load();

      final isClient = Platform.isAndroid ||
          (Platform.isWindows &&
              ObjectBoxService.instance.settings.isWindowsClient);
      final isHub = Platform.isWindows &&
          !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
      if (isClient && syncService != null) {
        syncService.pushMedicine(m);
      }
    }
  }

  void clearBatchesAndResetStock(List<int> medicineIds) {
    final medicines = _box.getMany(medicineIds);
    final List<Medicine> finalUpdates = [];
    final List<int> batchIdsToRemove = [];

    for (var m in medicines) {
      if (m != null) {
        batchIdsToRemove.addAll(m.batches.map((b) => b.id));
        m.batches.clear();
        m.mainStock = 0;
        m.storeStock = 0;
        m.bulkClinicStock = 0;
        m.bulkStoreStock = 0;
        m.updatedAt = DateTime.now();
        finalUpdates.add(m);
      }
    }

    if (batchIdsToRemove.isNotEmpty) {
      _batchBox.removeMany(batchIdsToRemove);
    }
    if (finalUpdates.isNotEmpty) {
      _box.putMany(finalUpdates);
    }
    load();

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    } else if (isClient) {
      for (var m in finalUpdates) {
        SyncQueueService.instance.addToQueue(
          entity: 'medicine',
          action: 'update',
          data: m.toJson(),
        );
      }
    }
  }

  void deleteBatch(Medicine m, MedicineBatch batch,
      {SyncService? syncService, AppUser? actor}) {
    // 1. Revert medicine's aggregate stock
    m.mainStock = (m.mainStock - batch.mainStock).clamp(0, 999999);
    m.storeStock = (m.storeStock - batch.storeStock).clamp(0, 999999);
    m.bulkClinicStock =
        (m.bulkClinicStock - batch.bulkClinicStock).clamp(0, 999999);
    m.bulkStoreStock =
        (m.bulkStoreStock - batch.bulkStoreStock).clamp(0, 999999);
    m.updatedAt = DateTime.now();

    // 2. Remove batch from medicine's ToMany (ObjectBox handles this but we need to put m)
    m.batches.removeWhere((b) => b.id == batch.id);
    _box.put(m);

    // 3. Delete the batch entity itself
    _batchBox.remove(batch.id);

    // Log batch deletion
    AuditService.instance.log(
      action: 'DELETE',
      entityType: 'MedicineBatch',
      entityId: batch.id.toString(),
      description: 'Deleted batch ${batch.batchNo} of ${m.name}',
      details: {
        'medicineId': m.id,
        'medicineName': m.name,
        'batchNo': batch.batchNo,
        'revertedMainStock': batch.mainStock,
        'revertedStoreStock': batch.storeStock,
      },
      actor: actor,
    );

    load();

    final isClient = Platform.isAndroid ||
        (Platform.isWindows &&
            ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows &&
        !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub && LocalServerService.instance.isRunning) {
      LocalServerService.instance.broadcast({'event': 'medicines_updated'});
    }
    if (isClient && syncService != null) {
      syncService.pushMedicine(m);
    }
  }

  void updateBatchDetail(
    Medicine m,
    MedicineBatch batch, {
    required String batchNo,
    required DateTime expiryDate,
    required int mainStock,
    required int storeStock,
    int bulkClinicStock = 0,
    int bulkStoreStock = 0,
    SyncService? syncService,
    AppUser? actor,
  }) {
    final oldBatchNo = batch.batchNo;
    final oldExpiryDate = batch.expiryDate;
    final oldMainStock = batch.mainStock;
    final oldStoreStock = batch.storeStock;
    final oldBulkClinicStock = batch.bulkClinicStock;
    final oldBulkStoreStock = batch.bulkStoreStock;

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

    // Log batch details modification
    AuditService.instance.log(
      action: 'UPDATE',
      entityType: 'MedicineBatch',
      entityId: batch.id.toString(),
      description: 'Modified batch details for ${m.name} (Batch: $oldBatchNo)',
      details: {
        'medicineId': m.id,
        'medicineName': m.name,
        'oldBatchNo': oldBatchNo,
        'newBatchNo': batchNo,
        'oldExpiryDate': oldExpiryDate.toIso8601String(),
        'newExpiryDate': expiryDate.toIso8601String(),
        'oldMainStock': oldMainStock,
        'newMainStock': mainStock,
        'oldStoreStock': oldStoreStock,
        'newStoreStock': storeStock,
        'oldBulkClinicStock': oldBulkClinicStock,
        'newBulkClinicStock': bulkClinicStock,
        'oldBulkStoreStock': oldBulkStoreStock,
        'newBulkStoreStock': bulkStoreStock,
      },
      actor: actor,
    );

    load();

    final isClient = Platform.isAndroid ||
        (Platform.isWindows &&
            ObjectBoxService.instance.settings.isWindowsClient);
    final isHub = Platform.isWindows &&
        !ObjectBoxService.instance.settings.isWindowsClient;
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
