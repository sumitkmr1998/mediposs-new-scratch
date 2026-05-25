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

  String? batchNo;
  @Property(type: PropertyType.date)
  DateTime? expiryDate;

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
    this.batchNo,
    this.expiryDate,
    DateTime? transferredAt,
    this.note = '',
    this.transferredBy = '',
  }) : transferredAt = transferredAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'qty': qty,
        'fromWarehouse': fromWarehouse,
        'toWarehouse': toWarehouse,
        'batchNo': batchNo,
        'expiryDate': expiryDate?.toIso8601String(),
        'transferredAt': transferredAt.toIso8601String(),
        'note': note,
        'transferredBy': transferredBy,
      };

  factory StockTransfer.fromJson(Map<String, dynamic> json) => StockTransfer(
        id: json['id'] ?? 0,
        medicineId: json['medicineId'],
        medicineName: json['medicineName'],
        qty: json['qty'],
        fromWarehouse: json['fromWarehouse'],
        toWarehouse: json['toWarehouse'],
        batchNo: json['batchNo'],
        expiryDate: DateTime.tryParse(json['expiryDate'] ?? ''),
        transferredAt: DateTime.tryParse(json['transferredAt'] ?? ''),
        note: json['note'] ?? '',
        transferredBy: json['transferredBy'] ?? '',
      );
}
