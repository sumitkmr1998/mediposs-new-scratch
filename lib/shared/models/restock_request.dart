import 'package:objectbox/objectbox.dart';

@Entity()
class RestockRequest {
  @Id()
  int id = 0;

  final int medicineId;
  final String medicineName;
  final int requestedQty;
  final String status; // 'PENDING', 'APPROVED', 'FULFILLED', 'REJECTED'
  
  @Property(type: PropertyType.date)
  final DateTime requestedAt;
  
  @Property(type: PropertyType.date)
  DateTime? fulfilledAt;
  
  final String? notes;

  RestockRequest({
    this.id = 0,
    required this.medicineId,
    required this.medicineName,
    required this.requestedQty,
    this.status = 'PENDING',
    required this.requestedAt,
    this.fulfilledAt,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'requestedQty': requestedQty,
        'status': status,
        'requestedAt': requestedAt.toIso8601String(),
        'fulfilledAt': fulfilledAt?.toIso8601String(),
        'notes': notes,
      };

  static RestockRequest fromJson(Map<String, dynamic> json) => RestockRequest(
        id: json['id'] ?? 0,
        medicineId: json['medicineId'] ?? 0,
        medicineName: json['medicineName'] ?? '',
        requestedQty: json['requestedQty'] ?? 0,
        status: json['status'] ?? 'PENDING',
        requestedAt: json['requestedAt'] != null
            ? DateTime.parse(json['requestedAt'])
            : DateTime.now(),
        fulfilledAt: json['fulfilledAt'] != null
            ? DateTime.parse(json['fulfilledAt'])
            : null,
        notes: json['notes'],
      );
}
