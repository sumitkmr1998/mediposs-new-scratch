import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/medicine.dart';
import '../models/sale.dart';
import '../models/appointment.dart';
import '../models/schedule_h1_record.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/time_service.dart';
import '../services/audit_service.dart';
import 'inventory_provider.dart';
import 'sales_provider.dart';
import 'prescription_provider.dart';
import 'opd_provider.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../services/firebase_sync_service.dart';

import '../../objectbox.g.dart';
import '../models/procedure.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/prescription.dart';
import 'patient_provider.dart';
import 'procedure_provider.dart';

class CartItem {
  final Medicine? medicine;
  final Procedure? procedure;
  int qty;
  double? customPrice; // For procedures

  CartItem({this.medicine, this.procedure, this.qty = 1, this.customPrice});

  double get lineTotal {
    if (medicine != null) return medicine!.sellingPrice * qty;
    if (procedure != null) return (customPrice ?? procedure!.basePrice) * qty;
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
    if (appt?.consultationBilled == true) return 0.0;
    return appt?.consultationFee ?? 0.0;
  }

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get taxRate => (_isClinicalDispense || ObjectBoxService.instance.settings.isCompositionScheme)
      ? 0.0
      : ObjectBoxService.instance.settings.taxRate / 100.0;

  double get taxAmount =>
      (subtotal - _discountAmount).clamp(0, double.infinity) * taxRate;

  double get total =>
      (subtotal - _discountAmount + taxAmount).clamp(0, double.infinity);

  double get totalRounded => (total * 10).round() / 10.0;

  bool get isEmpty => _items.isEmpty;

  void setClinicalDispense(bool val) {
    _isClinicalDispense = val;
    notifyListeners();
  }

  void addItem(Medicine medicine, {int qty = 1}) {
    final idx = _items.indexWhere((i) => i.medicine?.id == medicine.id && !i.isProcedure);
    if (idx >= 0) {
      _items[idx].qty += qty;
    } else {
      _items.add(CartItem(medicine: medicine, qty: qty));
    }
    notifyListeners();
  }

  void addProcedure(Procedure procedure, {double? price, int qty = 1}) {
    final idx = _items.indexWhere((i) => i.procedure?.id == procedure.id && i.isProcedure);
    if (idx >= 0) {
      _items[idx].qty += qty;
    } else {
      _items.add(CartItem(procedure: procedure, qty: qty, customPrice: price));
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
      _items[idx].qty = qty;
      notifyListeners();
    }
  }

  void updatePrice(int id, double price, {bool isProcedure = true}) {
    if (!isProcedure) return;
    final idx =
        _items.indexWhere((i) => i.procedure?.id == id && i.isProcedure);
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
    if (id != null) _patientId = id;
    if (uhid != null) _patientUhid = uhid;
    if (address != null) _patientAddress = address;
    notifyListeners();
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
    } else if (settings.storeAddress != null && settings.storeAddress!.trim().isNotEmpty) {
      doctorAddress = settings.storeAddress!.trim();
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
    for (final pName in procedures) {
      final proc = procProv.procedures.where((p) => p.name.toLowerCase() == pName.toLowerCase()).firstOrNull;
      if (proc != null) {
        addProcedure(proc);
      }
    }
  }

  void loadSaleForEditing(Sale sale) {
    clearCart();
    _editingSaleId = sale.id;
    _editingInvoiceNo = sale.invoiceNo;
    _editingCreatedAt = sale.createdAt;

    final db = ObjectBoxService.instance;
    final saleItems = _salesProvider.getSaleItems(sale);
    for (final item in saleItems) {
      if (item.isProcedure) {
        final proc = db.procedureBox.get(item.procedureId);
        if (proc != null) {
          addProcedure(proc, price: item.unitPrice, qty: item.qty.abs());
        } else {
          addProcedure(
            Procedure(name: item.medicineName, basePrice: item.unitPrice)..id = item.procedureId,
            price: item.unitPrice,
            qty: item.qty.abs(),
          );
        }
      } else {
        final med = db.medicineBox.get(item.medicineId);
        if (med != null) {
          addItem(med, qty: item.qty.abs());
        } else {
          addItem(
            Medicine(name: item.medicineName, sellingPrice: item.unitPrice, purchasePrice: 0)..id = item.medicineId,
            qty: item.qty.abs(),
          );
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
    
    _isClinicalDispense = sale.isClinicalDispense;
    _isReturnMode = sale.isReturn;
    _linkedAppointmentId = sale.linkedAppointmentId != 0 ? sale.linkedAppointmentId : null;
    _linkedProcedureId = sale.linkedProcedureId != 0 ? sale.linkedProcedureId : null;

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
              customPrice: i.customPrice))
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

    // If editing a sale, revert the original stock deductions first
    Map<String, dynamic> oldSaleJson = {};
    if (_editingSaleId != null) {
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
    final invoiceNo = '$prefix-$dateStr-$timeStr-$msStr';

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
            unitPrice: item.medicine!.sellingPrice,
            isProcedure: false,
            batchNo: 'N/A',
            expiryDate: '',
          ));
        } else {
          for (final db in deductedBatches) {
            final expiryStr = '${db.expiryDate.day.toString().padLeft(2, '0')}/${db.expiryDate.month.toString().padLeft(2, '0')}/${db.expiryDate.year}';
            saleItems.add(SaleItem(
              medicineId: item.medicine!.id,
              medicineName: item.name,
              qty: _isReturnMode ? -db.qty.abs() : db.qty,
              unitPrice: item.medicine!.sellingPrice,
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

    // Compute split logic
    double fCash = 0, fUpi = 0, fCard = 0;
    if (_paymentMethod == 'mixed') {
      fCash = _mixedCash;
      fUpi = _mixedUpi;
      fCard = _mixedCard;
      final appt = _linkedAppointmentId != null && _linkedAppointmentId != 0
          ? db.appointmentBox.get(_linkedAppointmentId!)
          : null;
      final apptPayMethod = appt?.paymentMethod ?? 'cash';
      if (apptPayMethod == 'upi') {
        fUpi += fee;
      } else if (apptPayMethod == 'card') {
        fCard += fee;
      } else {
        fCash += fee;
      }
    } else if (_paymentMethod == 'upi') {
      fUpi = finalTotalRounded;
    } else if (_paymentMethod == 'card') {
      fCard = finalTotalRounded;
    } else {
      fCash = finalTotalRounded;
    }

    if (_isReturnMode) {
      fCash = -fCash;
      fUpi = -fUpi;
      fCard = -fCard;
    }

    String resolvedOpdInvoiceNo = '';
    final apptId = _linkedAppointmentId;
    if (_isClinicalDispense && apptId != null && apptId != 0 && !_isReturnMode) {
      final appt = db.appointmentBox.get(apptId);
      if (appt != null) {
        final apptDate = appt.scheduledAt;
        final apptPhone = appt.patientPhone;
        final apptName = appt.patientName;
        final existingOpdSale = db.saleBox
            .query(Sale_.linkedAppointmentId.equals(appt.id)
                .and(Sale_.invoiceNo.startsWith('OPD-')))
            .build()
            .findFirst() ??
            db.saleBox.getAll().where((sale) {
              if (!sale.invoiceNo.startsWith('OPD-')) return false;
              final sameDay = sale.createdAt.year == apptDate.year &&
                  sale.createdAt.month == apptDate.month &&
                  sale.createdAt.day == apptDate.day;
              if (!sameDay) return false;

              if (apptPhone.isNotEmpty && sale.patientPhone == apptPhone) return true;
              if (apptName.toLowerCase().trim() == sale.patientName.toLowerCase().trim()) return true;
              return false;
            }).firstOrNull;
        if (existingOpdSale != null) {
          resolvedOpdInvoiceNo = existingOpdSale.invoiceNo;
        }
      }
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
      paymentMethod: _paymentMethod,
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

    db.saleBox.put(sale);

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
          db.appointmentBox.put(appt);

          // Find and remove the initial advance OPD consultation fee sale to prevent double counting.
          // Match by linkedAppointmentId or fall back to matching patient info and date for sync-robustness.
          final apptDate = appt.scheduledAt;
          final apptPhone = appt.patientPhone;
          final apptName = appt.patientName;
          final existingOpdSale = db.saleBox
              .query(Sale_.linkedAppointmentId.equals(appt.id)
                  .and(Sale_.invoiceNo.startsWith('OPD-')))
              .build()
              .findFirst() ??
              db.saleBox.getAll().where((sale) {
                if (!sale.invoiceNo.startsWith('OPD-')) return false;
                final sameDay = sale.createdAt.year == apptDate.year &&
                    sale.createdAt.month == apptDate.month &&
                    sale.createdAt.day == apptDate.day;
                if (!sameDay) return false;

                if (apptPhone.isNotEmpty && sale.patientPhone == apptPhone) return true;
                if (apptName.toLowerCase().trim() == sale.patientName.toLowerCase().trim()) return true;
                return false;
              }).firstOrNull;

          if (existingOpdSale != null) {
            db.saleBox.remove(existingOpdSale.id);
            if (isClient) {
              SyncQueueService.instance.addToQueue(
                entity: 'sale',
                action: 'delete',
                data: {'invoiceNo': existingOpdSale.invoiceNo},
              );
            }
          }

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
              .getAll()
              .where((x) => x.name == item.medicine!.name)
              .firstOrNull;
          if (m != null) {
            FirebaseSyncService.instance
                .broadcastUpdate('medicines', m.toJson());
          }
        }
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'sale',
        action: 'create',
        data: sale.toJson(),
      );
    }

    return sale;
    } finally {
      _isCheckingOut = false;
      notifyListeners();
    }
  }
}
