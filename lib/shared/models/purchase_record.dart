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

  String note;
  String supplier;

  PurchaseRecord({
    this.id = 0,
    required this.medicineId,
    required this.medicineName,
    required this.qty,
    required this.purchasePrice,
    DateTime? purchasedAt,
    this.note = '',
    this.supplier = '',
  }) : purchasedAt = purchasedAt ?? DateTime.now();
}
