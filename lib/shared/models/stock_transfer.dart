import 'package:objectbox/objectbox.dart';

@Entity()
class StockTransfer {
  @Id()
  int id = 0;

  int medicineId;
  String medicineName;

  int qty;
  String fromWarehouse; // 'main' or 'store'
  String toWarehouse; // 'main' or 'store'

  @Property(type: PropertyType.date)
  DateTime transferredAt;

  String note;
  String transferredBy;

  StockTransfer({
    this.id = 0,
    required this.medicineId,
    required this.medicineName,
    required this.qty,
    required this.fromWarehouse,
    required this.toWarehouse,
    DateTime? transferredAt,
    this.note = '',
    this.transferredBy = '',
  }) : transferredAt = transferredAt ?? DateTime.now();
}
