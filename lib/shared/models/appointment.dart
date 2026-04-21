import 'package:objectbox/objectbox.dart';

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
    this.isWalkIn = true,
    this.consultationBilled = false,
    this.paymentMethod = 'cash',
  }) : createdAt = createdAt ?? DateTime.now();
}
