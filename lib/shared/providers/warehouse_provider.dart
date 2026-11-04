import 'dart:io';
import 'package:flutter/material.dart';
import '../models/stock_transfer.dart';
import '../models/medicine.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/time_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/audit_service.dart';
import '../services/local_server_service.dart';
import '../services/firebase_sync_service.dart';
import '../../objectbox.g.dart';
import 'inventory_provider.dart';
import 'sales_provider.dart';
import '../domain/transfer_rules.dart';
import '../services/mutation_service.dart';

class WarehouseProvider extends ChangeNotifier {
  final InventoryProvider _inventoryProvider;

  WarehouseProvider(this._inventoryProvider) {
    _setToday();
  }

  List<StockTransfer> _transfers = [];
  List<StockTransfer> get transfers => List.unmodifiable(_transfers);

  SalesFilter _activeFilter = SalesFilter.today;
  DateTime? _customStart;
  DateTime? _customEnd;

  SalesFilter get activeFilter => _activeFilter;
  DateTime? get customStart => _customStart;
  DateTime? get customEnd => _customEnd;

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
              range.end.year, range.end.month, range.end.day, 23, 59, 59);
        }
        break;
    }
    loadTransfers();
  }

  void loadTransfers() {
    final box = ObjectBoxService.instance.transferBox;
    Query<StockTransfer> query;

    if (_customStart != null && _customEnd != null) {
      query = box
          .query(StockTransfer_.transferredAt.between(
              _customStart!.millisecondsSinceEpoch,
              _customEnd!.millisecondsSinceEpoch))
          .order(StockTransfer_.transferredAt, flags: Order.descending)
          .build();
    } else {
      query = box
          .query()
          .order(StockTransfer_.transferredAt, flags: Order.descending)
          .build();
    }

    _transfers = query.find();
    query.close();
    notifyListeners();
  }

  /// Transfer [qty] units from [from] warehouse to [to] warehouse for [medicine].
  /// Returns error message or null on success.
  Future<String?> transfer({
    required Medicine medicine,
    required int qty,
    required String from,
    required String to,
    String? batchNo,
    DateTime? expiryDate,
    String note = '',
    String transferredBy = '',
    SyncService? syncService,
    AppUser? actor,
  }) async {
    final validationError = TransferRules.validateEditTransfer(
      medicine: medicine,
      qty: qty,
      from: from,
      to: to,
      expiryDate: expiryDate,
      actor: actor,
    );
    if (validationError != null) return validationError;

    int getStockForLoc(Medicine m, String loc) {
      if (loc == 'main' || loc == 'clinic') return m.mainStock;
      if (loc == 'store') return m.storeStock;
      if (loc == 'bulkClinic') return m.bulkClinicStock;
      if (loc == 'bulkStore') return m.bulkStoreStock;
      return 0;
    }

    final initialFrom = getStockForLoc(medicine, from);
    final initialTo = getStockForLoc(medicine, to);

    // Update medicine stock via InventoryProvider
    _inventoryProvider.applyTransfer(
      medicineId: medicine.id,
      qty: qty,
      from: from,
      to: to,
      batchNo: batchNo,
      syncService: syncService,
      actor: actor,
    );

    final finalFrom = (initialFrom - qty).clamp(0, 999999);
    final finalTo = initialTo + qty;

    // Record transfer
    final now = await TimeService.getRobustTime();
    final transfer = StockTransfer(
      medicineId: medicine.id,
      medicineName: medicine.name,
      qty: qty,
      fromWarehouse: from,
      toWarehouse: to,
      batchNo: batchNo,
      expiryDate: expiryDate,
      note: note,
      transferredBy: transferredBy.isNotEmpty ? transferredBy : (actor?.name ?? 'System'),
      transferredAt: now,
      initialFromQty: initialFrom,
      finalFromQty: finalFrom,
      initialToQty: initialTo,
      finalToQty: finalTo,
    );
    ObjectBoxService.instance.transferBox.put(transfer);

    if (MutationService.instance.isClientDevice) {
      SyncQueueService.instance.addToQueue(
        entity: 'transfer',
        action: 'create',
        data: transfer.toJson(),
      );
    }

    loadTransfers();
    return null;
  }

  /// Edits an existing stock transfer.
  /// Reverts the previous stock movement, applies the updated transfer,
  /// and updates the StockTransfer record.
  /// Returns error message on failure or null on success.
  Future<String?> editTransfer({
    required StockTransfer originalTransfer,
    required int newQty,
    required String newFrom,
    required String newTo,
    String? newBatchNo,
    DateTime? newExpiryDate,
    String newNote = '',
    SyncService? syncService,
    AppUser? actor,
  }) async {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' ||
            actor.role.toLowerCase() == 'owner' ||
            actor.canEditTransfers)) {
      return 'Unauthorized: You do not have permission to edit stock transfers.';
    }

    if (newQty <= 0) {
      return 'Transfer quantity must be greater than zero.';
    }

    if (newFrom == newTo) {
      return 'Source and destination locations cannot be the same.';
    }

    final medicine = ObjectBoxService.instance.medicineBox.get(originalTransfer.medicineId);
    if (medicine == null) {
      return 'Medicine no longer exists in inventory.';
    }

    int getStockForLoc(Medicine m, String loc) {
      if (loc == 'main' || loc == 'clinic') return m.mainStock;
      if (loc == 'store') return m.storeStock;
      if (loc == 'bulkClinic') return m.bulkClinicStock;
      if (loc == 'bulkStore') return m.bulkStoreStock;
      return 0;
    }

    // 1. Temporarily revert the original transfer to restore stock
    _inventoryProvider.applyTransfer(
      medicineId: medicine.id,
      qty: originalTransfer.qty,
      from: originalTransfer.toWarehouse,
      to: originalTransfer.fromWarehouse,
      batchNo: originalTransfer.batchNo,
      syncService: syncService,
      actor: actor,
    );

    final refreshedMed = ObjectBoxService.instance.medicineBox.get(medicine.id) ?? medicine;

    // 2. Validate the new transfer parameters with the restored stock
    final validationError = TransferRules.validateEditTransfer(
      medicine: refreshedMed,
      qty: newQty,
      from: newFrom,
      to: newTo,
      expiryDate: newExpiryDate,
      actor: actor,
    );

    if (validationError != null) {
      // Revert the revert if validation fails
      _inventoryProvider.applyTransfer(
        medicineId: medicine.id,
        qty: originalTransfer.qty,
        from: originalTransfer.fromWarehouse,
        to: originalTransfer.toWarehouse,
        batchNo: originalTransfer.batchNo,
        syncService: syncService,
        actor: actor,
      );
      return validationError;
    }

    // Check batch stock if specific batch selected
    if (newBatchNo != null && newBatchNo.isNotEmpty) {
      final cleanBatch = newBatchNo.trim().toUpperCase();
      final batch = refreshedMed.batches
          .where((b) => b.batchNo.trim().toUpperCase() == cleanBatch)
          .firstOrNull;
      if (batch != null) {
        int availInBatch = 0;
        if (newFrom == 'main' || newFrom == 'clinic') {
          availInBatch = batch.mainStock;
        } else if (newFrom == 'store') {
          availInBatch = batch.storeStock;
        } else if (newFrom == 'bulkClinic') {
          availInBatch = batch.bulkClinicStock;
        } else if (newFrom == 'bulkStore') {
          availInBatch = batch.bulkStoreStock;
        }

        if (newQty > availInBatch) {
          // Revert back
          _inventoryProvider.applyTransfer(
            medicineId: medicine.id,
            qty: originalTransfer.qty,
            from: originalTransfer.fromWarehouse,
            to: originalTransfer.toWarehouse,
            batchNo: originalTransfer.batchNo,
            syncService: syncService,
            actor: actor,
          );
          return 'Insufficient stock in selected batch ($availInBatch available)';
        }
      }
    }

    final initialFrom = getStockForLoc(refreshedMed, newFrom);
    final initialTo = getStockForLoc(refreshedMed, newTo);

    // 3. Apply the updated transfer
    _inventoryProvider.applyTransfer(
      medicineId: refreshedMed.id,
      qty: newQty,
      from: newFrom,
      to: newTo,
      batchNo: newBatchNo,
      syncService: syncService,
      actor: actor,
    );

    final finalFrom = (initialFrom - newQty).clamp(0, 999999);
    final finalTo = initialTo + newQty;

    // 4. Update the transfer record
    originalTransfer
      ..qty = newQty
      ..fromWarehouse = newFrom
      ..toWarehouse = newTo
      ..batchNo = newBatchNo
      ..expiryDate = newExpiryDate
      ..note = newNote
      ..initialFromQty = initialFrom
      ..finalFromQty = finalFrom
      ..initialToQty = initialTo
      ..finalToQty = finalTo;

    ObjectBoxService.instance.transferBox.put(originalTransfer);

    // 5. Audit Log
    AuditService.instance.log(
      action: 'UPDATE',
      entityType: 'StockTransfer',
      entityId: originalTransfer.uuid,
      description: 'Edited transfer of ${medicine.name} to $newQty units from $newFrom to $newTo',
      details: originalTransfer.toJson(),
      actor: actor,
    );

    // 6. Sync mutation
    if (MutationService.instance.isClientDevice) {
      SyncQueueService.instance.addToQueue(
        entity: 'transfer',
        action: 'update',
        data: originalTransfer.toJson(),
      );
    } else {
      final isHub = Platform.isWindows &&
          !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'transfers_updated'});
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
      if (ObjectBoxService.instance.settings.firebaseEnabled) {
        FirebaseSyncService.instance
            .broadcastUpdate('transfers', originalTransfer.toJson());
      }
    }

    loadTransfers();
    return null;
  }

  /// Cancels an existing stock transfer, reverting its inventory movements.
  Future<String?> cancelTransfer({
    required StockTransfer transfer,
    SyncService? syncService,
    AppUser? actor,
  }) async {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' ||
            actor.role.toLowerCase() == 'owner' ||
            actor.canEditTransfers)) {
      return 'Unauthorized: You do not have permission to cancel stock transfers.';
    }

    final medicine = ObjectBoxService.instance.medicineBox.get(transfer.medicineId);
    if (medicine != null) {
      _inventoryProvider.applyTransfer(
        medicineId: medicine.id,
        qty: transfer.qty,
        from: transfer.toWarehouse,
        to: transfer.fromWarehouse,
        batchNo: transfer.batchNo,
        syncService: syncService,
        actor: actor,
      );
    }

    ObjectBoxService.instance.transferBox.remove(transfer.id);

    AuditService.instance.log(
      action: 'DELETE',
      entityType: 'StockTransfer',
      entityId: transfer.uuid,
      description:
          'Cancelled transfer of ${transfer.medicineName} (${transfer.qty} units from ${transfer.fromWarehouse} to ${transfer.toWarehouse})',
      details: transfer.toJson(),
      actor: actor,
    );

    if (MutationService.instance.isClientDevice) {
      SyncQueueService.instance.addToQueue(
        entity: 'transfer',
        action: 'delete',
        data: {'uuid': transfer.uuid, 'id': transfer.id},
      );
    } else {
      final isHub = Platform.isWindows &&
          !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'transfers_updated'});
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    }

    loadTransfers();
    return null;
  }

  int get pendingTransferCount {
    final today = DateTime.now();
    return _transfers
        .where((t) =>
            t.transferredAt.year == today.year &&
            t.transferredAt.month == today.month &&
            t.transferredAt.day == today.day)
        .length;
  }
}
