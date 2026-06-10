import 'package:flutter/material.dart';
import '../models/stock_transfer.dart';
import '../models/medicine.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/time_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../../objectbox.g.dart';
import 'inventory_provider.dart';
import 'sales_provider.dart';
import 'dart:io';

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
    if (qty <= 0) return 'Quantity must be greater than 0';

    int available = 0;
    if (from == 'main') available = medicine.mainStock;
    else if (from == 'store') available = medicine.storeStock;
    else if (from == 'bulkClinic') available = medicine.bulkClinicStock;
    else if (from == 'bulkStore') available = medicine.bulkStoreStock;

    String getLocName(String loc) {
      if (loc == 'main') return 'Clinic';
      if (loc == 'store') return 'Store';
      if (loc == 'bulkClinic') return 'Clinic Bulk';
      if (loc == 'bulkStore') return 'Store Bulk';
      return loc;
    }

    if (qty > available) {
      return 'Insufficient stock in ${getLocName(from)} (available: $available)';
    }

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
    );
    ObjectBoxService.instance.transferBox.put(transfer);

    if (Platform.isAndroid) {
      SyncQueueService.instance.addToQueue(
        entity: 'transfer',
        action: 'create',
        data: transfer.toJson(),
      );
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
