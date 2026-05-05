import 'package:objectbox/objectbox.dart';
import '../utils/date_helper.dart';

@Entity()
class Prescription {
  @Id()
  int id = 0;

  int appointmentId;
  int patientId;
  String patientName; // Denormalized
  int doctorId;
  String doctorName; // Denormalized

  String diagnosis;
  String complaints; // Chief complaints
  String notes; // Doctor's clinical notes

  // JSON arrays stored as strings for ObjectBox compatibility
  String itemsJson; // List<PrescriptionItem>
  String labTestsJson; // List<String> — test names requested
  String vitalsJson; // {bp, weight, temp, spo2, pulse}
  String imagesJson; // List<String> — paths to attached images

  bool dispensed; // Whether pharmacy has fulfilled this prescription

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  Prescription({
    this.id = 0,
    required this.appointmentId,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    this.diagnosis = '',
    this.complaints = '',
    this.notes = '',
    this.itemsJson = '[]',
    this.labTestsJson = '[]',
    this.vitalsJson = '{}',
    this.imagesJson = '[]',
    this.dispensed = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'appointmentId': appointmentId,
        'patientId': patientId,
        'patientName': patientName,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'diagnosis': diagnosis,
        'complaints': complaints,
        'notes': notes,
        'itemsJson': itemsJson,
        'labTestsJson': labTestsJson,
        'vitalsJson': vitalsJson,
        'imagesJson': imagesJson,
        'dispensed': dispensed,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Prescription.fromJson(Map<String, dynamic> json) => Prescription(
        id: json['id'] ?? 0,
        appointmentId: json['appointmentId'],
        patientId: json['patientId'],
        patientName: json['patientName'],
        doctorId: json['doctorId'],
        doctorName: json['doctorName'],
        diagnosis: json['diagnosis'] ?? '',
        complaints: json['complaints'] ?? '',
        notes: json['notes'] ?? '',
        itemsJson: json['itemsJson'] ?? '[]',
        labTestsJson: json['labTestsJson'] ?? '[]',
        vitalsJson: json['vitalsJson'] ?? '{}',
        imagesJson: json['imagesJson'] ?? '[]',
        dispensed: json['dispensed'] ?? false,
        createdAt: DateHelper.parseDateTime(json['createdAt']),
        updatedAt: DateHelper.parseDateTime(json['updatedAt']),
      );
}

// Transient models — not ObjectBox entities

class PrescriptionItem {
  final int medicineId;
  final String medicineName;
  final int qty;
  final String dosage; // e.g. "1-0-1 after meals"
  final int days;
  final bool isAvailable; // flag from inventory check

  PrescriptionItem({
    required this.medicineId,
    required this.medicineName,
    required this.qty,
    this.dosage = '',
    this.days = 1,
    this.isAvailable = true,
  });

  Map<String, dynamic> toJson() => {
        'medicineId': medicineId,
        'medicineName': medicineName,
        'qty': qty,
        'dosage': dosage,
        'days': days,
        'isAvailable': isAvailable,
      };

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) =>
      PrescriptionItem(
        medicineId: json['medicineId'],
        medicineName: json['medicineName'],
        qty: json['qty'],
        dosage: json['dosage'] ?? '',
        days: json['days'] ?? 1,
        isAvailable: json['isAvailable'] ?? true,
      );
}

class Vitals {
  final String bp; // e.g. "120/80"
  final String weight; // e.g. "65 kg"
  final String temp; // e.g. "98.6 F"
  final String spo2; // e.g. "98%"
  final String pulse; // e.g. "72 bpm"

  const Vitals({
    this.bp = '',
    this.weight = '',
    this.temp = '',
    this.spo2 = '',
    this.pulse = '',
  });

  Map<String, dynamic> toJson() => {
        'bp': bp,
        'weight': weight,
        'temp': temp,
        'spo2': spo2,
        'pulse': pulse,
      };

  factory Vitals.fromJson(Map<String, dynamic> json) => Vitals(
        bp: json['bp'] ?? '',
        weight: json['weight'] ?? '',
        temp: json['temp'] ?? '',
        spo2: json['spo2'] ?? '',
        pulse: json['pulse'] ?? '',
      );

  bool get isEmpty =>
      bp.isEmpty &&
      weight.isEmpty &&
      temp.isEmpty &&
      spo2.isEmpty &&
      pulse.isEmpty;
}
