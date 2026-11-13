import 'dart:convert';
import 'dart:async';
import '../services/device_identity_service.dart';
import 'package:flutter/foundation.dart';
import '../models/medicine.dart';
import '../models/sale.dart';
import '../models/appointment.dart';
import '../models/schedule_h1_record.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/time_service.dart';
import '../services/audit_service.dart';
import '../services/sales_fact_service.dart';
import 'inventory_provider.dart';
import 'sales_provider.dart';
import 'prescription_provider.dart';
import 'opd_provider.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import 'dart:io';
import '../services/firebase_sync_service.dart';

import '../../objectbox.g.dart';
import '../models/procedure.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/prescription.dart';
import 'patient_provider.dart';
import 'procedure_provider.dart';
import '../domain/sale_calculator.dart';

class CartItemBatchAllocation {
  final String batchNo;
  final int qty;
  final double unitPrice;
  final DateTime expiryDate;

  CartItemBatchAllocation({
    required this.batchNo,
    required this.qty,
    required this.unitPrice,
    required this.expiryDate,
  });

  double get total => qty * unitPrice;
}

class CartItem {
  final Medicine? medicine;
  final Procedure? procedure;
  int qty;
  double? customPrice; // For procedures or price overrides
  bool isClinicalDispense;

  CartItem({
    this.medicine,
    this.procedure,
    this.qty = 1,
    this.customPrice,
    this.isClinicalDispense = false,
  });

  /// Returns the FIFO batch breakdown based on available non-expired batches
  List<CartItemBatchAllocation> get batchBreakdown {
    if (medicine == null) return [];
    if (customPrice != null && customPrice! >= 0) {
      return [
        CartItemBatchAllocation(
          batchNo: (medicine!.getActiveBatch(isClinicalDispense) ?? medicine!.soonestExpiringBatch)?.batchNo ?? 'N/A',
          qty: qty,
          unitPrice: customPrice!,
          expiryDate: (medicine!.getActiveBatch(isClinicalDispense) ?? medicine!.soonestExpiringBatch)?.expiryDate ?? DateTime.now(),
        ),
      ];
    }

    final allocations = <CartItemBatchAllocation>[];
    int remaining = qty;
    final now = DateTime.now();

    final batches = medicine!.batches.toList();
    batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    for (final batch in batches) {
      if (remaining <= 0) break;
      if (batch.expiryDate.isBefore(now)) continue;

      final stock = isClinicalDispense ? batch.mainStock : batch.storeStock;
      if (stock > 0) {
        final take = remaining > stock ? stock : remaining;
        final price = batch.sellingPrice > 0 ? batch.sellingPrice : medicine!.sellingPrice;
        allocations.add(CartItemBatchAllocation(
          batchNo: batch.batchNo,
          qty: take,
          unitPrice: price,
          expiryDate: batch.expiryDate,
        ));
        remaining -= take;
      }
    }

    // Overflow or no stock available in batches - fallback to default medicine sellingPrice
    if (remaining > 0) {
      allocations.add(CartItemBatchAllocation(
        batchNo: 'N/A',
        qty: remaining,
        unitPrice: medicine!.sellingPrice,
        expiryDate: now,
      ));
    }

    return allocations;
  }

  /// Average or effective unit price across the quantity
  double get unitPrice {
    if (customPrice != null && customPrice! >= 0) return customPrice!;
    if (procedure != null) return procedure!.basePrice;
    if (medicine != null) {
      if (qty <= 0) {
        final ab = medicine!.getActiveBatch(isClinicalDispense) ?? medicine!.soonestExpiringBatch;
        if (ab != null && ab.sellingPrice > 0) return ab.sellingPrice;
        return medicine!.sellingPrice;
      }
      return lineTotal / qty;
    }
    return 0;
  }

  /// Exact total taking into account each batch's individual price and quantity
  double get lineTotal {
    if (customPrice != null && customPrice! >= 0) return customPrice! * qty;
    if (procedure != null) return procedure!.basePrice * qty;
    if (medicine != null) {
      final allocations = batchBreakdown;
      if (allocations.isNotEmpty) {
        return allocations.fold(0.0, (sum, a) => sum + a.total);
      }
      return medicine!.sellingPrice * qty;
    }
    return 0;
  }

  String get name => medicine?.name ?? procedure?.name ?? 'Unknown';
  int get id => medicine?.id ?? procedure?.id ?? 0;
  bool get isProcedure => procedure != null;
}

class PendingCart {
  final List<CartItem> items;
  final double discountAmount;
  final String patientName;
  final String patientPhone;
  final String patientUhid;
  final int patientId;
  final String paymentMethod;
  final double mixedCash;
  final double mixedUpi;
  final double mixedCard;
  final int? linkedPrescriptionId;
  final int? linkedAppointmentId;
  final int? linkedProcedureId;
  final bool isReturnMode;
  final bool isClinicalDispense;
  final DateTime heldAt;

  PendingCart({
    required this.items,
    required this.discountAmount,
    required this.patientName,
    required this.patientPhone,
    required this.patientUhid,
    required this.patientId,
    required this.paymentMethod,
    required this.mixedCash,
    required this.mixedUpi,
    required this.mixedCard,
    this.linkedPrescriptionId,
    this.linkedAppointmentId,
    this.linkedProcedureId,
    required this.isReturnMode,
    this.isClinicalDispense = false,
    required this.heldAt,
  });

  double get total => items.fold(0.0, (sum, item) => sum + item.lineTotal) - discountAmount;
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
  bool _isCheckingOut = false;
  double _discountAmount = 0;
  String _patientName = '';
  String _patientPhone = '';
  String _patientUhid = '';
  int _patientId = 0;
  String _paymentMethod = 'cash';
  bool _isReturnMode = false;

  double _mixedCash = 0;
  double _mixedUpi = 0;
  double _mixedCard = 0;

  bool _isClinicalDispense = false;

  int? _linkedPrescriptionId;
  int? _linkedAppointmentId;
  int? _linkedProcedureId;
  
  // H1 Compliance Info
  String _doctorName = '';
  String _doctorAddress = '';
  String _doctorRegistrationNo = '';
  String _patientAddress = '';

  String get doctorName => _doctorName;
  String get doctorAddress => _doctorAddress;
  String get doctorRegistrationNo => _doctorRegistrationNo;
  String get patientAddress => _patientAddress;

  bool get hasScheduleH1Items => _items.any((i) => i.medicine?.isScheduleH1 == true);

  final List<PendingCart> _pendingCarts = [];

  // Editing Sale Mode
  int? _editingSaleId;
  String? _editingInvoiceNo;
  DateTime? _editingCreatedAt;

  int? get editingSaleId => _editingSaleId;
  String? get editingInvoiceNo => _editingInvoiceNo;
  bool get isEditingSale => _editingSaleId != null;

  List<CartItem> get items => List.unmodifiable(_items);
  List<PendingCart> get pendingCarts => List.unmodifiable(_pendingCarts);
  double get discountAmount => _discountAmount;
  String get patientName => _patientName;
  String get patientNameStr => _patientName;
  String get patientPhone => _patientPhone;
  String get patientUhid => _patientUhid;
  int get patientId => _patientId;
  String get paymentMethod => _paymentMethod;
  bool get isReturnMode => _isReturnMode;
  bool get isClinicalDispense => _isClinicalDispense;
  int? get linkedAppointmentId => _linkedAppointmentId;
  int? get linkedProcedureId => _linkedProcedureId;

  double get mixedCash => _mixedCash;
  double get mixedUpi => _mixedUpi;
  double get mixedCard => _mixedCard;

  double get linkedConsultationFee {
    if (!_isClinicalDispense) return 0.0;
    if (_linkedAppointmentId == null || _linkedAppointmentId == 0) return 0.0;
    final appt = ObjectBoxService.instance.appointmentBox.get(_linkedAppointmentId!);
    if (appt == null) return 0.0;
    if (appt.consultationBilled) return 0.0;
    return appt.consultationFee;
  }

  SaleTotals get _totals => SaleCalculator.calculate(
        items: _items,
        discountAmount: _discountAmount,
        storeTaxRate: ObjectBoxService.instance.settings.taxRate,
        isClinicalDispense: _isClinicalDispense,
        isCompositionScheme: ObjectBoxService.instance.settings.isCompositionScheme,
      );

  double get subtotal => _totals.subtotal;

  double get taxRate => _totals.taxRate;

  double get taxAmount => _totals.taxAmount;

  double get total => _totals.total;

  double get totalRounded => _totals.totalRounded;

  bool get isEmpty => _items.isEmpty;

  void setClinicalDispense(bool val) {
    _isClinicalDispense = val;
    for (final item in _items) {
      item.isClinicalDispense = val;
    }
    notifyListeners();
  }

  void addItem(Medicine medicine, {int qty = 1}) {
    final idx = _items.indexWhere((i) => i.medicine?.id == medicine.id && !i.isProcedure);
    final maxStock = _isClinicalDispense ? medicine.mainStock : medicine.storeStock;
    if (idx >= 0) {
      final currentQty = _items[idx].qty;
      if (!_isReturnMode && currentQty + qty > maxStock) {
        _items[idx].qty = maxStock;
      } else {
        _items[idx].qty += qty;
      }
    } else {
      int finalQty = qty;
      if (!_isReturnMode && qty > maxStock) {
        finalQty = maxStock;
      }
      if (finalQty > 0 || _isReturnMode) {
        _items.add(CartItem(
          medicine: medicine,
          qty: finalQty,
          isClinicalDispense: _isClinicalDispense,
        ));
      }
    }
    notifyListeners();
  }

  void addProcedure(Procedure procedure, {double? price, int qty = 1}) {
    final idx = _items.indexWhere((i) => i.procedure?.id == procedure.id && i.isProcedure);
    if (idx >= 0) {
      _items[idx].qty += qty;
    } else {
      _items.add(CartItem(
        procedure: procedure,
        qty: qty,
        customPrice: price,
        isClinicalDispense: _isClinicalDispense,
      ));
    }
    notifyListeners();
  }

  void updateProcedurePrice(int id, double newPrice) {
    final idx = _items.indexWhere((i) => i.procedure?.id == id && i.isProcedure);
    if (idx >= 0) {
      _items[idx].customPrice = newPrice;
      notifyListeners();
    }
  }

  void removeItem(int id, {bool isProcedure = false}) {
    if (isProcedure) {
      _items.removeWhere((i) => i.procedure?.id == id && i.isProcedure);
    } else {
      _items.removeWhere((i) => i.medicine?.id == id && !i.isProcedure);
    }
    notifyListeners();
  }

  void removeLastItem() {
    if (_items.isNotEmpty) {
      _items.removeLast();
      notifyListeners();
    }
  }

  void updateQty(int id, int qty, {bool isProcedure = false}) {
    if (qty <= 0) {
      removeItem(id, isProcedure: isProcedure);
      return;
    }
    final idx = _items.indexWhere((i) =>
        (isProcedure ? i.procedure?.id : i.medicine?.id) == id &&
        i.isProcedure == isProcedure);
    if (idx >= 0) {
      if (!isProcedure && !_isReturnMode && _editingSaleId == null) {
        final medicine = _items[idx].medicine;
        if (medicine != null) {
          final maxStock = _isClinicalDispense ? medicine.mainStock : medicine.storeStock;
          if (qty > maxStock) {
            qty = maxStock;
          }
        }
      }
      _items[idx].qty = qty;
      notifyListeners();
    }
  }

  void updatePrice(int id, double price, {bool isProcedure = true}) {
    final idx = isProcedure
        ? _items.indexWhere((i) => i.procedure?.id == id && i.isProcedure)
        : _items.indexWhere((i) => i.medicine?.id == id && !i.isProcedure);
    if (idx >= 0) {
      _items[idx].customPrice = price;
      notifyListeners();
    }
  }

  void setDiscount(double amount) {
    _discountAmount = amount < 0 ? 0 : amount;
    notifyListeners();
  }

  void setPatient({String? name, String? phone, int? id, String? uhid, String? address}) {
    if (name != null) _patientName = name;
    if (phone != null) _patientPhone = phone;
    if (id != null) {
      final oldId = _patientId;
      _patientId = id;
      if (id > 0 && id != oldId && _editingSaleId == null && !_isReturnMode) {
        Future.microtask(() {
          checkAndLoadPrescriptionForPatient(id);
        });
      }
    }
    if (uhid != null) _patientUhid = uhid;
    if (address != null) _patientAddress = address;
    notifyListeners();
  }

  void checkAndLoadPrescriptionForPatient(int patientId) {
    if (patientId <= 0) return;
    try {
      final pBox = ObjectBoxService.instance.prescriptionBox;
      final prescription = pBox
          .query(Prescription_.patientId.equals(patientId).and(Prescription_.dispensed.equals(false)))
          .order(Prescription_.createdAt, flags: Order.descending)
          .build()
          .findFirst();
      if (prescription != null) {
        debugPrint('CartProvider: Found undispensed prescription ID ${prescription.id} for patient ID $patientId. Auto-loading...');
        loadPrescriptionIntoCartInternal(prescription);
      }
    } catch (e) {
      debugPrint('CartProvider: Error checking prescription for patient: $e');
    }
  }

  void loadPrescriptionIntoCartInternal(Prescription prescription) {
    clearCart();
    setClinicalDispense(true);
    if (prescription.appointmentId != 0) {
      setLinkedAppointment(prescription.appointmentId);
    }
    
    var patientPhone = '';
    if (prescription.appointmentId != 0) {
      final appt = ObjectBoxService.instance.store.box<Appointment>().get(prescription.appointmentId);
      if (appt != null) {
        patientPhone = appt.patientPhone;
      }
    }

    Patient? patient = ObjectBoxService.instance.patientBox.get(prescription.patientId);
    _patientName = prescription.patientName;
    _patientPhone = patient?.phone ?? patientPhone;
    _patientId = patient?.id ?? 0;
    _patientUhid = patient?.uhid ?? '';
    _patientAddress = patient?.address ?? '';
    setLinkedPrescription(prescription.id);

    final docBox = ObjectBoxService.instance.store.box<Doctor>();
    var doctorObj = docBox.get(prescription.doctorId);
    if (doctorObj == null && prescription.doctorName.isNotEmpty) {
      doctorObj = docBox.query(Doctor_.name.equals(prescription.doctorName, caseSensitive: false)).build().findFirst();
    }
    
    final settings = ObjectBoxService.instance.settings;
    String doctorAddress = '';
    if (doctorObj != null && doctorObj.address.trim().isNotEmpty) {
      doctorAddress = doctorObj.address.trim();
    } else if (settings.clinicAddress != null && settings.clinicAddress!.trim().isNotEmpty) {
      doctorAddress = settings.clinicAddress!.trim();
    } else if (settings.storeAddress.trim().isNotEmpty) {
      doctorAddress = settings.storeAddress.trim();
    }

    setH1PrescriptionDetails(
      doctorName: prescription.doctorName,
      doctorAddress: doctorAddress,
      doctorRegistrationNo: doctorObj?.registrationNo ?? '',
      patientAddress: patient?.address ?? '',
    );

    // Extract prescription items
    List<PrescriptionItem> pItems = [];
    try {
      final List<dynamic> decoded = jsonDecode(prescription.itemsJson);
      pItems = decoded.map((j) => PrescriptionItem.fromJson(j)).toList();
    } catch (_) {}

    for (final pItem in pItems) {
      final medicine = ObjectBoxService.instance.medicineBox
          .query(Medicine_.name.equals(pItem.medicineName, caseSensitive: false))
          .build()
          .findFirst();

      if (medicine != null) {
        addItem(medicine, qty: pItem.qty);
      }
    }

    // Extract procedures
    List<String> procedures = [];
    try {
      final List<dynamic> decoded = jsonDecode(prescription.proceduresJson);
      procedures = decoded.cast<String>();
    } catch (_) {}

    for (final pEntry in procedures) {
      final parts = pEntry.split('||');
      final pName = parts[0];
      final price = parts.length > 1 ? double.tryParse(parts[1]) : null;
      final proc = ObjectBoxService.instance.procedureBox
          .query(Procedure_.name.equals(pName, caseSensitive: false))
          .build()
          .findFirst();
      if (proc != null) {
        addProcedure(proc, price: price);
      } else {
        // Fallback for custom/unregistered procedure names
        addProcedure(
          Procedure(name: pName, basePrice: price ?? 0.0),
          price: price,
        );
      }
    }
  }

  void setH1PrescriptionDetails({required String doctorName, required String doctorAddress, required String doctorRegistrationNo, required String patientAddress}) {
    _doctorName = doctorName;
    _doctorAddress = doctorAddress;
    _doctorRegistrationNo = doctorRegistrationNo;
    _patientAddress = patientAddress;
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

  void setLinkedAppointment(int? id) {
    _linkedAppointmentId = id;
    notifyListeners();
  }

  void setLinkedProcedure(int? id) {
    _linkedProcedureId = id;
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _discountAmount = 0;
    _patientName = '';
    _patientPhone = '';
    _patientId = 0;
    _patientUhid = '';
    _paymentMethod = 'cash';
    _mixedCash = 0;
    _mixedUpi = 0;
    _mixedCard = 0;
    _linkedPrescriptionId = null;
    _linkedAppointmentId = null;
    _linkedProcedureId = null;
    _isClinicalDispense = false;
    _editingSaleId = null;
    _editingInvoiceNo = null;
    _editingCreatedAt = null;
    _doctorName = '';
    _doctorAddress = '';
    _doctorRegistrationNo = '';
    _patientAddress = '';
    notifyListeners();
  }

  void loadPrescriptionIntoCart({
    required Prescription prescription,
    required InventoryProvider inv,
    required PatientProvider patientProv,
    required PrescriptionProvider pProvider,
    required ProcedureProvider procProv,
  }) {
    clearCart();
    setClinicalDispense(true);
    if (prescription.appointmentId != 0) {
      setLinkedAppointment(prescription.appointmentId);
    }
    var patientPhone = '';
    if (prescription.appointmentId != 0) {
      final apptBox = ObjectBoxService.instance.store.box<Appointment>();
      final appt = apptBox.get(prescription.appointmentId);
      if (appt != null) {
        patientPhone = appt.patientPhone;
      }
    }

    Patient? patient;
    if (prescription.patientId != 0) {
      final p = patientProv.getById(prescription.patientId);
      if (p != null && p.name.trim().toLowerCase() == prescription.patientName.trim().toLowerCase()) {
        patient = p;
      }
    }
    if (patient == null && (prescription.patientName.isNotEmpty || patientPhone.isNotEmpty)) {
      patient = patientProv.getByInfo(prescription.patientName, patientPhone);
    }
    if (patient == null && prescription.patientName.isNotEmpty) {
      final cleanName = prescription.patientName.trim().toLowerCase();
      patient = patientProv.patients
          .where((p) => p.name.trim().toLowerCase() == cleanName)
          .firstOrNull;
    }

    setPatient(
      name: prescription.patientName,
      phone: patient?.phone ?? patientPhone,
      id: patient?.id ?? 0,
      uhid: patient?.uhid ?? '',
      address: patient?.address ?? '',
    );
    setLinkedPrescription(prescription.id);

    final docBox = ObjectBoxService.instance.store.box<Doctor>();
    var doctorObj = docBox.get(prescription.doctorId);
    if (doctorObj == null && prescription.doctorName.isNotEmpty) {
      doctorObj = docBox.query(Doctor_.name.equals(prescription.doctorName, caseSensitive: false)).build().findFirst();
    }
    
    final settings = ObjectBoxService.instance.settings;
    String doctorAddress = '';
    if (doctorObj != null && doctorObj.address.trim().isNotEmpty) {
      doctorAddress = doctorObj.address.trim();
    } else if (settings.clinicAddress != null && settings.clinicAddress!.trim().isNotEmpty) {
      doctorAddress = settings.clinicAddress!.trim();
    } else if (settings.storeAddress.trim().isNotEmpty) {
      doctorAddress = settings.storeAddress.trim();
    }

    setH1PrescriptionDetails(
      doctorName: prescription.doctorName,
      doctorAddress: doctorAddress,
      doctorRegistrationNo: doctorObj?.registrationNo ?? '',
      patientAddress: patient?.address ?? '',
    );

    final items = pProvider.getItems(prescription);

    for (final pItem in items) {
      final medicine = inv.medicines
          .where(
            (m) => m.name.toLowerCase() == pItem.medicineName.toLowerCase(),
          )
          .firstOrNull;

      if (medicine != null) {
        addItem(medicine, qty: pItem.qty);
      }
    }

    final procedures = pProvider.getProcedures(prescription);
    for (final pEntry in procedures) {
      final parts = pEntry.split('||');
      final pName = parts[0];
      final price = parts.length > 1 ? double.tryParse(parts[1]) : null;
      final proc = procProv.procedures.where((p) => p.name.toLowerCase() == pName.toLowerCase()).firstOrNull;
      if (proc != null) {
        addProcedure(proc, price: price);
      } else {
        addProcedure(
          Procedure(name: pName, basePrice: price ?? 0.0),
          price: price,
        );
      }
    }
  }

  void loadSaleForEditing(Sale sale) {
    clearCart();
    _editingSaleId = sale.id;
    _editingInvoiceNo = sale.invoiceNo;
    _editingCreatedAt = sale.createdAt;
    _isClinicalDispense = sale.isClinicalDispense;
    _isReturnMode = sale.isReturn;

    final db = ObjectBoxService.instance;
    final saleItems = _salesProvider.getSaleItems(sale);
    for (final item in saleItems) {
      if (item.isProcedure) {
        Procedure? proc = db.procedureBox.get(item.procedureId);
        if (proc == null || proc.name.toLowerCase() != item.medicineName.toLowerCase()) {
          proc = db.procedureBox
              .query(Procedure_.name.equals(item.medicineName, caseSensitive: false))
              .build()
              .findFirst();
        }
        proc ??= Procedure(
          name: item.medicineName,
          basePrice: item.unitPrice,
        )..id = item.procedureId;

        final existingIdx = _items.indexWhere((i) => i.procedure?.id == proc!.id && i.isProcedure);
        if (existingIdx >= 0) {
          _items[existingIdx].qty += item.qty.abs();
        } else {
          _items.add(CartItem(
            procedure: proc,
            qty: item.qty.abs(),
            customPrice: item.unitPrice,
          ));
        }
      } else {
        // 1. Try to find medicine by ID first if valid
        Medicine? med = (item.medicineId > 0) ? db.medicineBox.get(item.medicineId) : null;
        // 2. If not found or name doesn't match, find by case-insensitive name
        if (med == null || med.name.toLowerCase() != item.medicineName.toLowerCase()) {
          med = db.medicineBox
              .query(Medicine_.name.equals(item.medicineName, caseSensitive: false))
              .build()
              .findFirst();
        }

        // 3. If still null, create fallback Medicine with item name and price
        med ??= Medicine(
          name: item.medicineName,
          sellingPrice: item.unitPrice,
          purchasePrice: 0,
        )..id = item.medicineId;

        // 4. Directly add to cart items with preserved price and quantity WITHOUT stock limit clamping!
        final existingIdx = _items.indexWhere((i) => i.medicine?.id == med!.id && !i.isProcedure);
        if (existingIdx >= 0) {
          _items[existingIdx].qty += item.qty.abs();
        } else {
          _items.add(CartItem(
            medicine: med,
            qty: item.qty.abs(),
            customPrice: item.unitPrice,
            isClinicalDispense: _isClinicalDispense,
          ));
        }
      }
    }

    _patientName = sale.patientName;
    _patientPhone = sale.patientPhone;
    _patientId = sale.patientId;
    _patientUhid = sale.patientUhid;
    _paymentMethod = sale.paymentMethod;
    
    _discountAmount = sale.isReturn ? -sale.discount : sale.discount;
    
    if (_paymentMethod == 'mixed') {
      _mixedCash = sale.isReturn ? -sale.cashAmount : sale.cashAmount;
      _mixedUpi = sale.isReturn ? -sale.upiAmount : sale.upiAmount;
      _mixedCard = sale.isReturn ? -sale.cardAmount : sale.cardAmount;
    }
    
    _linkedAppointmentId = sale.linkedAppointmentId != 0 ? sale.linkedAppointmentId : null;
    _linkedProcedureId = sale.linkedProcedureId != 0 ? sale.linkedProcedureId : null;

    debugPrint('CartProvider: Loaded ${sale.invoiceNo} with ${_items.length} item(s) for editing.');
    notifyListeners();
  }

  void holdCurrentCart() {
    if (_items.isEmpty) return;
    _pendingCarts.add(PendingCart(
      items: _items
          .map((i) => CartItem(
              medicine: i.medicine,
              procedure: i.procedure,
              qty: i.qty,
              customPrice: i.customPrice,
              isClinicalDispense: i.isClinicalDispense))
          .toList(),
      discountAmount: _discountAmount,
      patientName: _patientName,
      patientPhone: _patientPhone,
      patientUhid: _patientUhid,
      patientId: _patientId,
      paymentMethod: _paymentMethod,
      mixedCash: _mixedCash,
      mixedUpi: _mixedUpi,
      mixedCard: _mixedCard,
      linkedPrescriptionId: _linkedPrescriptionId,
      linkedAppointmentId: _linkedAppointmentId,
      linkedProcedureId: _linkedProcedureId,
      isReturnMode: _isReturnMode,
      isClinicalDispense: _isClinicalDispense,
      heldAt: DateTime.now(),
    ));
    clearCart();
  }

  void restoreCart(PendingCart pending) {
    _items.clear();
    _items.addAll(pending.items);
    _discountAmount = pending.discountAmount;
    _patientName = pending.patientName;
    _patientPhone = pending.patientPhone;
    _patientUhid = pending.patientUhid;
    _patientId = pending.patientId;
    _paymentMethod = pending.paymentMethod;
    _mixedCash = pending.mixedCash;
    _mixedUpi = pending.mixedUpi;
    _mixedCard = pending.mixedCard;
    _linkedPrescriptionId = pending.linkedPrescriptionId;
    _linkedAppointmentId = pending.linkedAppointmentId;
    _linkedProcedureId = pending.linkedProcedureId;
    _isReturnMode = pending.isReturnMode;
    _isClinicalDispense = pending.isClinicalDispense;
    _pendingCarts.remove(pending);
    notifyListeners();
  }

  void deletePendingCart(PendingCart pending) {
    _pendingCarts.remove(pending);
    notifyListeners();
  }

  /// Completes checkout: saves sale, deducts storeStock, clears cart.
  /// Returns the created Sale on success.
  Future<Sale?> checkout([SyncService? syncService, AppUser? actor]) async {
    if (_items.isEmpty || _isCheckingOut) return null;
    _isCheckingOut = true;
    notifyListeners();

    try {

    final db = ObjectBoxService.instance;
    final settings = db.settings;
    final isClient = Platform.isAndroid || (Platform.isWindows && settings.isWindowsClient);
    final isHub = Platform.isWindows && !settings.isWindowsClient;
    final isEdit = _editingSaleId != null;

    // If editing a sale, revert the original stock deductions first
    Map<String, dynamic> oldSaleJson = {};
    if (isEdit) {
      final oldSale = db.saleBox.get(_editingSaleId!);
      if (oldSale != null) {
        oldSaleJson = oldSale.toJson();
        final oldItems = _salesProvider.getSaleItems(oldSale);
        for (final item in oldItems) {
          if (oldSale.isClinicalDispense) {
            _inventoryProvider.deductClinicStock(item.medicineId, -item.qty);
          } else {
            _inventoryProvider.deductStoreStock(item.medicineId, -item.qty);
          }
        }
      }
    }

    // Build invoice number: (RET/INV/DISP)-YYYYMMDD-HHMMSS-MS
    final now = await TimeService.getRobustTime();
    final prefix = _isReturnMode ? 'RET' : (_isClinicalDispense ? 'DISP' : 'INV');
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final msStr = now.millisecond.toString().padLeft(3, '0');
    final deviceCode = await DeviceIdentityService.getDeviceCode();
    var invoiceNo = '$prefix-$dateStr-$timeStr-$deviceCode';
    final existingCheck = db.saleBox.query(Sale_.invoiceNo.equals(invoiceNo)).build();
    if (existingCheck.findFirst() != null) {
      invoiceNo = '$prefix-$dateStr-$timeStr-$msStr-$deviceCode';
    }
    existingCheck.close();

    // Build items and Deduct or Restock stock (storeStock vs mainStock)
    final saleItems = <SaleItem>[];

    final fee = _isClinicalDispense ? linkedConsultationFee : 0.0;
    if (fee > 0) {
      saleItems.add(SaleItem(
        medicineId: 0,
        procedureId: 0,
        medicineName: 'Consultation Fee',
        qty: 1,
        unitPrice: fee,
        isProcedure: true,
      ));
    }

    for (final item in _items) {
      if (item.isProcedure) {
        saleItems.add(SaleItem(
          medicineId: 0,
          procedureId: item.procedure?.id ?? 0,
          medicineName: item.name,
          qty: _isReturnMode ? -item.qty : item.qty,
          unitPrice: item.customPrice ?? item.procedure?.basePrice ?? 0,
          isProcedure: true,
          batchNo: '',
          expiryDate: '',
        ));
      } else {
        final qtyToDeduct = _isReturnMode ? -item.qty : item.qty;
        List<DeductedBatch> deductedBatches;
        if (_isClinicalDispense) {
          deductedBatches = _inventoryProvider.deductClinicStock(item.medicine!.id, qtyToDeduct);
        } else {
          deductedBatches = _inventoryProvider.deductStoreStock(item.medicine!.id, qtyToDeduct);
        }

        if (deductedBatches.isEmpty) {
          saleItems.add(SaleItem(
            medicineId: item.medicine!.id,
            medicineName: item.name,
            qty: qtyToDeduct,
            unitPrice: item.unitPrice,
            isProcedure: false,
            batchNo: 'N/A',
            expiryDate: '',
          ));
        } else {
          for (final db in deductedBatches) {
            final expiryStr = '${db.expiryDate.day.toString().padLeft(2, '0')}/${db.expiryDate.month.toString().padLeft(2, '0')}/${db.expiryDate.year}';
            final batchPrice = db.sellingPrice > 0 ? db.sellingPrice : (item.unitPrice > 0 ? item.unitPrice : item.medicine!.sellingPrice);
            saleItems.add(SaleItem(
              medicineId: item.medicine!.id,
              medicineName: item.name,
              qty: _isReturnMode ? -db.qty.abs() : db.qty,
              unitPrice: batchPrice,
              isProcedure: false,
              batchNo: db.batchNo,
              expiryDate: expiryStr,
            ));
          }
        }
      }
    }

    final finalSubtotal = subtotal + fee;
    final finalTaxAmount = taxAmount;
    final finalTotal = (finalSubtotal - _discountAmount + finalTaxAmount).clamp(0.0, double.infinity);
    final finalTotalRounded = (finalTotal * 10).round() / 10.0;

    // Locate linked appointment and any prior advance OPD sale for merging
    final apptId = _linkedAppointmentId;
    final appt = (_isClinicalDispense && apptId != null && apptId != 0 && !_isReturnMode)
        ? db.appointmentBox.get(apptId)
        : null;

    Sale? existingOpdSale;
    if (_isClinicalDispense && appt != null) {
      // 1. Try match by OPD invoice note tag [OPD_INV:...]
      final match = RegExp(r'\[OPD_INV:(OPD-[^\]]+)\]').firstMatch(appt.notes);
      if (match != null) {
        final targetInv = match.group(1)!;
        existingOpdSale = db.saleBox.query(Sale_.invoiceNo.equals(targetInv)).build().findFirst();
      }

      // 2. Try match by linkedAppointmentId
      if (existingOpdSale == null) {
        existingOpdSale = db.saleBox
            .query(Sale_.linkedAppointmentId.equals(appt.id)
                .and(Sale_.invoiceNo.startsWith('OPD-')))
            .build()
                .findFirst();
      }

      // 3. Fallback: match by date and patient info
      if (existingOpdSale == null) {
        final apptDate = appt.scheduledAt;
        final startOfDay = DateTime(apptDate.year, apptDate.month, apptDate.day);
        final endOfDay = DateTime(apptDate.year, apptDate.month, apptDate.day, 23, 59, 59);
        final candidateSales = db.saleBox
            .query(Sale_.invoiceNo.startsWith('OPD-').and(Sale_.createdAt.between(startOfDay.millisecondsSinceEpoch, endOfDay.millisecondsSinceEpoch)))
            .build()
            .find();
        existingOpdSale = candidateSales.where((s) {
          if (appt.patientId > 0 && s.patientId == appt.patientId) return true;
          if (appt.patientPhone.isNotEmpty && s.patientPhone == appt.patientPhone) return true;
          if (appt.patientName.toLowerCase().trim() == s.patientName.toLowerCase().trim()) return true;
          return false;
        }).firstOrNull;
      }
    }

    final resolvedOpdInvoiceNo = existingOpdSale?.invoiceNo ?? '';

    // Compute split logic: merge prior advance OPD payment with pharmacy counter payment
    double counterCash = 0, counterUpi = 0, counterCard = 0;
    if (_paymentMethod == 'mixed') {
      counterCash = _mixedCash;
      counterUpi = _mixedUpi;
      counterCard = _mixedCard;
    } else if (_paymentMethod == 'upi') {
      counterUpi = totalRounded;
    } else if (_paymentMethod == 'card') {
      counterCard = totalRounded;
    } else {
      counterCash = totalRounded;
    }

    double opdCash = 0, opdUpi = 0, opdCard = 0;
    if (fee > 0) {
      if (existingOpdSale != null) {
        opdCash = existingOpdSale.cashAmount;
        opdUpi = existingOpdSale.upiAmount;
        opdCard = existingOpdSale.cardAmount;
        if (opdCash == 0 && opdUpi == 0 && opdCard == 0) {
          final m = existingOpdSale.paymentMethod;
          if (m == 'upi') {
            opdUpi = fee;
          } else if (m == 'card') {
            opdCard = fee;
          } else {
            opdCash = fee;
          }
        }
      } else if (appt != null) {
        final m = appt.paymentMethod;
        if (m == 'upi') {
          opdUpi = fee;
        } else if (m == 'card') {
          opdCard = fee;
        } else {
          opdCash = fee;
        }
      }
    }

    double fCash = counterCash + opdCash;
    double fUpi = counterUpi + opdUpi;
    double fCard = counterCard + opdCard;

    if (_isReturnMode) {
      fCash = -fCash;
      fUpi = -fUpi;
      fCard = -fCard;
    }

    final String finalPaymentMethod;
    if (fCash > 0 && fUpi == 0 && fCard == 0) {
      finalPaymentMethod = 'cash';
    } else if (fUpi > 0 && fCash == 0 && fCard == 0) {
      finalPaymentMethod = 'upi';
    } else if (fCard > 0 && fCash == 0 && fUpi == 0) {
      finalPaymentMethod = 'card';
    } else {
      finalPaymentMethod = 'mixed';
    }

    final sale = Sale(
      id: _editingSaleId ?? 0,
      invoiceNo: _editingInvoiceNo ?? invoiceNo,
      patientId: _patientId,
      patientName: _patientName,
      patientPhone: _patientPhone,
      patientUhid: _patientUhid,
      subtotal: _isReturnMode ? -finalSubtotal : finalSubtotal,
      discount: _isReturnMode ? -_discountAmount : _discountAmount,
      taxRate: (_isClinicalDispense || settings.isCompositionScheme) ? 0.0 : settings.taxRate,
      taxAmount: _isReturnMode ? -finalTaxAmount : finalTaxAmount,
      total: _isReturnMode ? -finalTotalRounded : finalTotalRounded,
      paymentMethod: finalPaymentMethod,
      cashAmount: fCash,
      upiAmount: fUpi,
      cardAmount: fCard,
      isReturn: _isReturnMode,
      isClinicalDispense: _isClinicalDispense,
      linkedAppointmentId: _linkedAppointmentId ?? 0,
      linkedProcedureId: _linkedProcedureId ?? 0,
      opdInvoiceNo: resolvedOpdInvoiceNo,
      itemsJson: jsonEncode(saleItems.map((i) => i.toJson()).toList()),
      createdAt: _editingCreatedAt ?? now,
    );

    db.store.runInTransaction(TxMode.write, () {
      db.saleBox.put(sale);
      if (isClient) {
        SyncQueueService.instance.enqueue(
          entity: 'sale',
          action: isEdit ? 'update' : 'create',
          data: sale.toJson(),
        );
      }
    });
    _applySalesFacts(sale, isEdit: _editingSaleId != null, oldSaleJson: oldSaleJson);

    // Log the transaction
    if (_editingSaleId != null) {
      AuditService.instance.log(
        action: 'UPDATE',
        entityType: 'Sale',
        entityId: sale.invoiceNo,
        description: 'Edited Sale: invoice ${sale.invoiceNo}, net amount ₹${sale.total}',
        details: {
          'before': oldSaleJson,
          'after': sale.toJson(),
        },
        actor: actor,
      );
    } else {
      AuditService.instance.log(
        action: sale.isReturn ? 'VOID' : 'CREATE',
        entityType: 'Sale',
        entityId: sale.invoiceNo,
        description: sale.isReturn
            ? 'Processed Return/Refund: invoice ${sale.invoiceNo}, amount ₹${sale.total}'
            : 'Created POS Sale: invoice ${sale.invoiceNo}, net amount ₹${sale.total}',
        details: {
          'invoiceNo': sale.invoiceNo,
          'total': sale.total,
          'isReturn': sale.isReturn,
          'isClinicalDispense': sale.isClinicalDispense,
          'patientName': sale.patientName,
        },
        actor: actor,
      );
    }

    // Save Schedule H1 records if applicable
    if (hasScheduleH1Items) {
      for (final item in saleItems) {
        if (item.isProcedure) continue;
        final med = db.medicineBox.get(item.medicineId);
        if (med != null && med.isScheduleH1) {
          final h1Record = ScheduleH1Record(
            saleDate: sale.createdAt,
            medicineName: item.medicineName,
            batchNo: item.batchNo,
            quantity: item.qty,
            patientName: sale.patientName,
            patientAddress: _patientAddress,
            patientPhone: sale.patientPhone,
            doctorName: _doctorName,
            doctorAddress: _doctorAddress,
            doctorRegistrationNo: _doctorRegistrationNo,
            linkedSaleId: sale.id,
            invoiceNo: sale.invoiceNo,
          );
          final recId = db.store.box<ScheduleH1Record>().put(h1Record);
          h1Record.id = recId;

          if (isClient) {
            SyncQueueService.instance.addToQueue(
              entity: 'h1_record',
              action: 'create',
              data: h1Record.toJson(),
            );
          }
        }
      }
    }

    _editingSaleId = null;
    _editingInvoiceNo = null;
    _editingCreatedAt = null;

    // Mark prescription as dispensed if linked
    if (_linkedPrescriptionId != null) {
      _prescriptionProvider.markDispensed(_linkedPrescriptionId!,
          syncService: syncService);
    }

    // OPD Queue Automation: Mark today's active appointment as Done and consultation fee as billed
    if (_isClinicalDispense && apptId != null && apptId != 0 && !_isReturnMode) {
      var appt = db.appointmentBox.get(apptId);
      if (appt != null) {
        if (appt.status != kStatusDone) {
          await _opdProvider.updateStatus(appt.id, kStatusDone, syncService);
          // Reload from DB to get updated status and times from updateStatus to prevent stale data write
          appt = db.appointmentBox.get(apptId) ?? appt;
        }

        if (!appt.consultationBilled) {
          appt.consultationBilled = true;
          appt.updatedAt = DateTime.now();
          db.appointmentBox.put(appt);

          if (isClient) {
            SyncQueueService.instance.addToQueue(
              entity: 'appointment',
              action: 'update',
              data: appt.toJson(),
            );
          } else if (isHub && LocalServerService.instance.isRunning) {
            LocalServerService.instance.broadcast({'event': 'appointments_updated'});
          }
        }

        // Merge & remove the prior advance OPD sale to prevent duplicate transactions
        if (existingOpdSale != null) {
          db.saleBox.remove(existingOpdSale.id);
          try {
            SalesFactService.instance.reverseSale(existingOpdSale);
          } catch (e) {
            debugPrint('CartProvider: Error reversing OPD sale facts: $e');
          }

          await AuditService.instance.log(
            action: 'VOID',
            entityType: 'Sale',
            entityId: existingOpdSale.invoiceNo,
            description: 'Merged OPD Receipt into Dispense Bill: invoice ${existingOpdSale.invoiceNo}',
            details: existingOpdSale.toJson(),
            actor: actor,
          );

          if (isClient) {
            SyncQueueService.instance.addToQueue(
              entity: 'sale',
              action: 'delete',
              data: {'invoiceNo': existingOpdSale.invoiceNo},
            );
          } else if (isHub && LocalServerService.instance.isRunning) {
            LocalServerService.instance.broadcast({
              'event': 'sale_deleted',
              'invoiceNo': existingOpdSale.invoiceNo,
            });
            unawaited(FirebaseSyncService.instance
                .deleteDocument('sales', existingOpdSale.invoiceNo)
                .catchError((_) {}));
          }
        }
      }
    }

    _salesProvider.load();

    clearCart();

    // Broadcast or Push network sync
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
        LocalServerService.instance.broadcast({'event': 'sales_updated'});
        LocalServerService.instance.broadcast({'event': 'medicines_updated'});
        
        // Push to Firebase for offline companion fallback
        FirebaseSyncService.instance.broadcastUpdate('sales', sale.toJson());
        // Also push updated medicines (stock deducted)
        for (final item in _items) {
          if (item.isProcedure || item.medicine == null) continue;
          final m = ObjectBoxService.instance.medicineBox
              .query(Medicine_.name.equals(item.medicine!.name))
              .build()
              .findFirst();
          if (m != null) {
            FirebaseSyncService.instance
                .broadcastUpdate('medicines', m.toJson());
          }
        }
      }
    } else if (isClient) {
      SyncQueueService.instance.processQueue();
    }
    return sale;
    } finally {
      _isCheckingOut = false;
      notifyListeners();
    }
  }

  void _applySalesFacts(
    Sale sale, {
    required bool isEdit,
    required Map<String, dynamic> oldSaleJson,
  }) {
    try {
      final facts = SalesFactService.instance;
      if (isEdit && oldSaleJson.isNotEmpty) {
        facts.reverseSale(Sale.fromJson(oldSaleJson));
      }
      facts.applySale(sale);
    } catch (e) {
      debugPrint('CartProvider: sales fact update failed: $e');
    }
  }
}
