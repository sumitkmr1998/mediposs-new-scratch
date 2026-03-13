import 'package:objectbox/objectbox.dart';

@Entity()
class Sale {
  @Id()
  int id = 0;

  String invoiceNo;
  int patientId; // Link to Patient entity
  String patientName;
  String patientPhone;

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

  bool synced;
  bool isReturn;

  // Stored as JSON string for ObjectBox compatibility
  String itemsJson;

  Sale({
    this.id = 0,
    required this.invoiceNo,
    this.patientId = 0,
    this.patientName = '',
    this.patientPhone = '',
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
    this.synced = false,
    this.isReturn = false,
    this.itemsJson = '[]',
  }) : createdAt = createdAt ?? DateTime.now();
}

// Transient model (not an ObjectBox entity)
class SaleItem {
  final int medicineId;
  final String medicineName;
  final int qty;
  final double unitPrice;
  double get lineTotal => qty * unitPrice;

  SaleItem({
    required this.medicineId,
    required this.medicineName,
    required this.qty,
    required this.unitPrice,
  });

  Map<String, dynamic> toJson() => {
        'medicineId': medicineId,
        'medicineName': medicineName,
        'qty': qty,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        medicineId: json['medicineId'],
        medicineName: json['medicineName'],
        qty: json['qty'],
        unitPrice: (json['unitPrice'] as num).toDouble(),
      );
}
