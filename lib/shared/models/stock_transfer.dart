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

  int initialFromQty;
  int finalFromQty;
  int initialToQty;
  int finalToQty;

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
    this.initialFromQty = 0,
    this.finalFromQty = 0,
    this.initialToQty = 0,
    this.finalToQty = 0,
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
        'initialFromQty': initialFromQty,
        'finalFromQty': finalFromQty,
        'initialToQty': initialToQty,
        'finalToQty': finalToQty,
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
        initialFromQty: json['initialFromQty'] ?? 0,
        finalFromQty: json['finalFromQty'] ?? 0,
        initialToQty: json['initialToQty'] ?? 0,
        finalToQty: json['finalToQty'] ?? 0,
      );
}
