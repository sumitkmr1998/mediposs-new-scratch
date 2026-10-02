import 'package:objectbox/objectbox.dart';
import 'package:uuid/uuid.dart';

@Entity()
class PurchaseRecord {
  @Id()
  int id = 0;

  @Index()
  String uuid;

  int medicineId;
  String medicineName;
  int qty;
  double purchasePrice; // Price at the time of purchase

  @Property(type: PropertyType.date)
  DateTime purchasedAt;

  String location; // Target warehouse/location ('clinic', 'store', 'bulkClinic', 'bulkStore')
  String note;
  String supplier;
  String batchNo;

  @Property(type: PropertyType.date)
  DateTime? expiryDate;

  int initialQty;
  int finalQty;

  PurchaseRecord({
    this.id = 0,
    String? uuid,
    required this.medicineId,
    required this.medicineName,
    required this.qty,
    required this.purchasePrice,
    DateTime? purchasedAt,
    this.location = '',
    this.note = '',
    this.supplier = '',
    this.batchNo = '',
    this.expiryDate,
    this.initialQty = 0,
    this.finalQty = 0,
  })  : uuid = (uuid != null && uuid.isNotEmpty) ? uuid : const Uuid().v4(),
        purchasedAt = purchasedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'qty': qty,
        'purchasePrice': purchasePrice,
        'purchasedAt': purchasedAt.toIso8601String(),
        'location': location,
        'note': note,
        'supplier': supplier,
        'batchNo': batchNo,
        'expiryDate': expiryDate?.toIso8601String(),
        'initialQty': initialQty,
        'finalQty': finalQty,
      };

  factory PurchaseRecord.fromJson(Map<String, dynamic> json) => PurchaseRecord(
        id: json['id'] ?? 0,
        uuid: json['uuid'] as String?,
        medicineId: json['medicineId'] ?? 0,
        medicineName: json['medicineName'] ?? '',
        qty: json['qty'] ?? 0,
        purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0.0,
        purchasedAt: DateTime.tryParse(json['purchasedAt'] ?? ''),
        location: json['location'] ?? '',
        note: json['note'] ?? '',
        supplier: json['supplier'] ?? '',
        batchNo: json['batchNo'] as String? ?? '',
        expiryDate: DateTime.tryParse(json['expiryDate'] ?? ''),
        initialQty: json['initialQty'] ?? 0,
        finalQty: json['finalQty'] ?? 0,
      );
}

