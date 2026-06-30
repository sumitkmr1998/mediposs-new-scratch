import 'package:objectbox/objectbox.dart';
import '../utils/date_helper.dart';

// Status constants
const String kStatusWaiting = 'waiting';
const String kStatusWithDoctor = 'with_doctor';
const String kStatusPharmacy = 'pharmacy';
const String kStatusDone = 'done';
const String kStatusCancelled = 'cancelled';

@Entity()
class Appointment {
  @Id()
  int id = 0;

  int patientId;
  String patientName; // Denormalized for quick display
  String patientPhone; // Denormalized

  int doctorId;
  String doctorName; // Denormalized

  int tokenNumber;
  String status; // waiting / with_doctor / pharmacy / done / cancelled

  double consultationFee;
  String notes; // Doctor's quick notes

  @Property(type: PropertyType.date)
  DateTime scheduledAt;

  @Property(type: PropertyType.date)
  DateTime? calledAt;

  @Property(type: PropertyType.date)
  DateTime? pharmacyAt;

  @Property(type: PropertyType.date)
  DateTime? completedAt;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool isWalkIn; // Walk-in vs advance booking
  bool consultationBilled; // Whether fee was added to POS
  String paymentMethod; // cash / upi / card / pending

  Appointment({
    this.id = 0,
    required this.patientId,
    required this.patientName,
    this.patientPhone = '',
    required this.doctorId,
    required this.doctorName,
    required this.tokenNumber,
    this.status = kStatusWaiting,
    this.consultationFee = 0,
    this.notes = '',
    required this.scheduledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isWalkIn = true,
    this.consultationBilled = false,
    this.paymentMethod = 'cash',
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientId': patientId,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'tokenNumber': tokenNumber,
        'status': status,
        'consultationFee': consultationFee,
        'notes': notes,
        'scheduledAt': scheduledAt.toIso8601String(),
        'calledAt': calledAt?.toIso8601String(),
        'pharmacyAt': pharmacyAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isWalkIn': isWalkIn,
        'consultationBilled': consultationBilled,
        'paymentMethod': paymentMethod,
      };

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] ?? 0,
        patientId: json['patientId'],
        patientName: json['patientName'],
        patientPhone: json['patientPhone'] ?? '',
        doctorId: json['doctorId'],
        doctorName: json['doctorName'],
        tokenNumber: json['tokenNumber'],
        status: json['status'] ?? kStatusWaiting,
        consultationFee: (json['consultationFee'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] ?? '',
        scheduledAt: DateHelper.parseDateTime(json['scheduledAt']) ?? DateTime.now(),
        createdAt: DateHelper.parseDateTime(json['createdAt']),
        isWalkIn: json['isWalkIn'] ?? true,
        consultationBilled: json['consultationBilled'] ?? false,
        paymentMethod: json['paymentMethod'] ?? 'cash',
      )
        ..calledAt = DateHelper.parseDateTime(json['calledAt'])
        ..pharmacyAt = DateHelper.parseDateTime(json['pharmacyAt'])
        ..completedAt = DateHelper.parseDateTime(json['completedAt'])
        ..updatedAt = DateHelper.parseDateTime(json['updatedAt']) ??
            DateHelper.parseDateTime(json['createdAt']) ??
            DateTime.now();
}
