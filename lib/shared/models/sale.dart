import 'package:objectbox/objectbox.dart';
import '../utils/date_helper.dart';

@Entity()
class Sale {
  @Id()
  int id = 0;

  String invoiceNo;
  int patientId; // Link to Patient entity
  String patientName;
  String patientPhone;
  String patientUhid;

  double subtotal;
  double discount;
  double taxRate;
  double taxAmount;
  double total;

  String paymentMethod; // cash, card, upi, or mixed

  double cashAmount;
  double upiAmount;
  double cardAmount;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool synced;
  bool isReturn;
  bool isClinicalDispense;

  int linkedAppointmentId; // Link to Appointment (if clinical dispense)
  int linkedProcedureId;   // Link to Procedure (if clinical dispense)

  // Stored as JSON string for ObjectBox compatibility
  String itemsJson;

  Sale({
    this.id = 0,
    required this.invoiceNo,
    this.patientId = 0,
    this.patientName = '',
    this.patientPhone = '',
    this.patientUhid = '',
    required this.subtotal,
    this.discount = 0,
    this.taxRate = 0,
    this.taxAmount = 0,
    required this.total,
    this.paymentMethod = 'cash',
    this.cashAmount = 0,
    this.upiAmount = 0,
    this.cardAmount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.synced = false,
    this.isReturn = false,
    this.isClinicalDispense = false,
    this.linkedAppointmentId = 0,
    this.linkedProcedureId = 0,
    this.itemsJson = '[]',
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceNo': invoiceNo,
        'patientId': patientId,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'patientUhid': patientUhid,
        'subtotal': subtotal,
        'discount': discount,
        'taxRate': taxRate,
        'taxAmount': taxAmount,
        'total': total,
        'paymentMethod': paymentMethod,
        'cashAmount': cashAmount,
        'upiAmount': upiAmount,
        'cardAmount': cardAmount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'synced': synced,
        'isReturn': isReturn,
        'isClinicalDispense': isClinicalDispense,
        'linkedAppointmentId': linkedAppointmentId,
        'linkedProcedureId': linkedProcedureId,
        'itemsJson': itemsJson,
      };

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] ?? 0,
        invoiceNo: json['invoiceNo'],
        patientId: json['patientId'] ?? 0,
        patientName: json['patientName'] ?? '',
        patientPhone: json['patientPhone'] ?? '',
        patientUhid: json['patientUhid'] ?? '',
        subtotal: (json['subtotal'] as num).toDouble(),
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
        taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num).toDouble(),
        paymentMethod: json['paymentMethod'] ?? 'cash',
        cashAmount: (json['cashAmount'] as num?)?.toDouble() ?? 0,
        upiAmount: (json['upiAmount'] as num?)?.toDouble() ?? 0,
        cardAmount: (json['cardAmount'] as num?)?.toDouble() ?? 0,
        createdAt: DateHelper.parseDateTime(json['createdAt']),
        updatedAt: DateHelper.parseDateTime(json['updatedAt']),
        synced: json['synced'] ?? false,
        isReturn: json['isReturn'] ?? false,
        isClinicalDispense: json['isClinicalDispense'] ?? false,
        linkedAppointmentId: json['linkedAppointmentId'] ?? 0,
        linkedProcedureId: json['linkedProcedureId'] ?? 0,
        itemsJson: json['itemsJson'] ?? '[]',
      );
}

// Transient model (not an ObjectBox entity)
class SaleItem {
  final int medicineId;
  final int procedureId;
  final String medicineName;
  final int qty;
  final double unitPrice;
  final bool isProcedure;
  final String batchNo;
  final String expiryDate;

  double get lineTotal => qty * unitPrice;

  SaleItem({
    this.medicineId = 0,
    this.procedureId = 0,
    required this.medicineName,
    required this.qty,
    required this.unitPrice,
    this.isProcedure = false,
    this.batchNo = '',
    this.expiryDate = '',
  });

  Map<String, dynamic> toJson() => {
        'medicineId': medicineId,
        'procedureId': procedureId,
        'medicineName': medicineName,
        'qty': qty,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
        'isProcedure': isProcedure,
        'batchNo': batchNo,
        'expiryDate': expiryDate,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        medicineId: json['medicineId'] ?? 0,
        procedureId: json['procedureId'] ?? 0,
        medicineName: json['medicineName'],
        qty: json['qty'],
        unitPrice: (json['unitPrice'] as num).toDouble(),
        isProcedure: json['isProcedure'] ?? false,
        batchNo: json['batchNo'] ?? '',
        expiryDate: json['expiryDate'] ?? '',
      );
}
