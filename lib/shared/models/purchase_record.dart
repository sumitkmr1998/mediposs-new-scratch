import 'package:objectbox/objectbox.dart';

@Entity()
class PurchaseRecord {
  @Id()
  int id = 0;

  int medicineId;
  String medicineName;
  int qty;
  double purchasePrice; // Price at the time of purchase

  @Property(type: PropertyType.date)
  DateTime purchasedAt;

  String location; // Target warehouse/location ('clinic', 'store', 'bulkClinic', 'bulkStore')
  String note;
  String supplier;

  PurchaseRecord({
    this.id = 0,
    required this.medicineId,
    required this.medicineName,
    required this.qty,
    required this.purchasePrice,
    DateTime? purchasedAt,
    this.location = '',
    this.note = '',
    this.supplier = '',
  }) : purchasedAt = purchasedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'qty': qty,
        'purchasePrice': purchasePrice,
        'purchasedAt': purchasedAt.toIso8601String(),
        'location': location,
        'note': note,
        'supplier': supplier,
      };

  factory PurchaseRecord.fromJson(Map<String, dynamic> json) => PurchaseRecord(
        id: json['id'] ?? 0,
        medicineId: json['medicineId'],
        medicineName: json['medicineName'],
        qty: json['qty'],
        purchasePrice: (json['purchasePrice'] as num).toDouble(),
        purchasedAt: DateTime.tryParse(json['purchasedAt'] ?? ''),
        location: json['location'] ?? '',
        note: json['note'] ?? '',
        supplier: json['supplier'] ?? '',
      );
}
