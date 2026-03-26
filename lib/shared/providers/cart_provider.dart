import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/medicine.dart';
import '../models/sale.dart';
import '../models/appointment.dart';
import '../services/objectbox_service.dart';
import '../services/time_service.dart';
import 'inventory_provider.dart';
import 'sales_provider.dart';
import 'prescription_provider.dart';
import 'opd_provider.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import 'dart:io';
import 'package:provider/provider.dart';

class CartItem {
  final Medicine medicine;
  int qty;

  CartItem({required this.medicine, this.qty = 1});

  double get lineTotal => medicine.sellingPrice * qty;
}

class CartProvider extends ChangeNotifier {
  final InventoryProvider _inventoryProvider;
  final SalesProvider _salesProvider;
  final PrescriptionProvider _prescriptionProvider;
  final OpdProvider _opdProvider;

  CartProvider(
    this._inventoryProvider,
    this._salesProvider,
    this._prescriptionProvider,
    this._opdProvider,
  );

  final List<CartItem> _items = [];
  double _discountAmount = 0;
  String _patientName = '';
  String _patientPhone = '';
  int _patientId = 0;
  String _paymentMethod = 'cash';
  bool _isReturnMode = false;

  double _mixedCash = 0;
  double _mixedUpi = 0;
  double _mixedCard = 0;

  int? _linkedPrescriptionId;

  List<CartItem> get items => List.unmodifiable(_items);
  double get discountAmount => _discountAmount;
  String get patientName => _patientName;
  String get patientNameStr => _patientName;
  String get patientPhone => _patientPhone;
  int get patientId => _patientId;
  String get paymentMethod => _paymentMethod;
  bool get isReturnMode => _isReturnMode;

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get taxRate => ObjectBoxService.instance.settings.taxRate / 100.0;

  double get taxAmount =>
      (subtotal - _discountAmount).clamp(0, double.infinity) * taxRate;

  double get total =>
      (subtotal - _discountAmount + taxAmount).clamp(0, double.infinity);

  double get totalRounded => (total * 10).round() / 10.0;

  bool get isEmpty => _items.isEmpty;

  void addItem(Medicine medicine, {int qty = 1}) {
    final idx = _items.indexWhere((i) => i.medicine.id == medicine.id);
    if (idx >= 0) {
      _items[idx].qty += qty;
    } else {
      _items.add(CartItem(medicine: medicine, qty: qty));
    }
    notifyListeners();
  }

  void removeItem(int medicineId) {
    _items.removeWhere((i) => i.medicine.id == medicineId);
    notifyListeners();
  }

  void removeLastItem() {
    if (_items.isNotEmpty) {
      _items.removeLast();
      notifyListeners();
    }
  }

  void updateQty(int medicineId, int qty) {
    if (qty <= 0) {
      removeItem(medicineId);
      return;
    }
    final idx = _items.indexWhere((i) => i.medicine.id == medicineId);
    if (idx >= 0) {
      _items[idx].qty = qty;
      notifyListeners();
    }
  }

  void setDiscount(double amount) {
    _discountAmount = amount < 0 ? 0 : amount;
    notifyListeners();
  }

  void setPatient({String name = '', String phone = '', int id = 0}) {
    _patientName = name;
    _patientPhone = phone;
    _patientId = id;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    // reset mixed amounts when changing methods
    if (method != 'mixed') {
      _mixedCash = 0;
      _mixedUpi = 0;
      _mixedCard = 0;
    }
    notifyListeners();
  }

  void setMixedAmounts(double cash, double upi, double card) {
    _mixedCash = cash;
    _mixedUpi = upi;
    _mixedCard = card;
    notifyListeners();
  }

  void toggleReturnMode() {
    clearCart();
    _isReturnMode = !_isReturnMode;
    notifyListeners();
  }

  void setLinkedPrescription(int? id) {
    _linkedPrescriptionId = id;
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _discountAmount = 0;
    _patientName = '';
    _patientPhone = '';
    _patientId = 0;
    _paymentMethod = 'cash';
    _mixedCash = 0;
    _mixedUpi = 0;
    _mixedCard = 0;
    _linkedPrescriptionId = null;
    notifyListeners();
  }

  /// Completes checkout: saves sale, deducts storeStock, clears cart.
  /// Returns the created Sale on success.
  Future<Sale?> checkout([SyncService? syncService]) async {
    if (_items.isEmpty) return null;

    final db = ObjectBoxService.instance;
    final settings = db.settings;

    // Build invoice number: (RET/INV)-YYYYMMDD-NNNN
    final now = await TimeService.getRobustTime();
    final count = db.saleBox.count();
    final prefix = _isReturnMode ? 'RET' : 'INV';
    final invoiceNo =
        '$prefix-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(count + 1).toString().padLeft(4, '0')}';

    // Build items (returns have negative quantities inherently when we record them in the DB to keep history straight)
    final saleItems = _items.map(
      (i) => SaleItem(
        medicineId: i.medicine.id,
        medicineName: i.medicine.name,
        qty: _isReturnMode ? -i.qty : i.qty,
        unitPrice: i.medicine.sellingPrice,
      ),
    );

    // Deduct or Restock storeStock
    for (final item in _items) {
      if (_isReturnMode) {
        // Restock
        _inventoryProvider.deductStoreStock(item.medicine.id, -item.qty);
      } else {
        // Deduct
        _inventoryProvider.deductStoreStock(item.medicine.id, item.qty);
      }
    }

    // Compute split logic
    double fCash = 0, fUpi = 0, fCard = 0;
    if (_paymentMethod == 'mixed') {
      fCash = _mixedCash;
      fUpi = _mixedUpi;
      fCard = _mixedCard;
    } else if (_paymentMethod == 'upi') {
      fUpi = totalRounded;
    } else if (_paymentMethod == 'card') {
      fCard = totalRounded;
    } else {
      fCash = totalRounded;
    }

    if (_isReturnMode) {
      fCash = -fCash;
      fUpi = -fUpi;
      fCard = -fCard;
    }

    final sale = Sale(
      invoiceNo: invoiceNo,
      patientId: _patientId,
      patientName: _patientName,
      patientPhone: _patientPhone,
      subtotal: _isReturnMode ? -subtotal : subtotal,
      discount: _isReturnMode ? -_discountAmount : _discountAmount,
      taxRate: settings.taxRate,
      taxAmount: _isReturnMode ? -taxAmount : taxAmount,
      total: _isReturnMode ? -totalRounded : totalRounded,
      paymentMethod: _paymentMethod,
      cashAmount: fCash,
      upiAmount: fUpi,
      cardAmount: fCard,
      isReturn: _isReturnMode,
      itemsJson: jsonEncode(saleItems.map((i) => i.toJson()).toList()),
      createdAt: now,
    );

    db.saleBox.put(sale);
    _salesProvider.load();

    // Mark prescription as dispensed if linked
    if (_linkedPrescriptionId != null) {
      _prescriptionProvider.markDispensed(_linkedPrescriptionId!,
          syncService: syncService);
    }

    // OPD Queue Automation: Mark today's active appointment as Done
    if (_patientId != 0 && !_isReturnMode) {
      final activeAppt = _opdProvider.todayQueue
          .where((a) =>
              a.patientId == _patientId &&
              (a.status == kStatusWaiting ||
                  a.status == kStatusWithDoctor ||
                  a.status == kStatusPharmacy))
          .firstOrNull;

      if (activeAppt != null) {
        _opdProvider.updateStatus(activeAppt.id, kStatusDone, syncService);
      }
    }

    clearCart();

    // Broadcast or Push network sync
    if (Platform.isWindows) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
      }
    } else if (Platform.isAndroid && syncService != null) {
      await syncService.pushSale(sale);
    }

    return sale;
  }
}
