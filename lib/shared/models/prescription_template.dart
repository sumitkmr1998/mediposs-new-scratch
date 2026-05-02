import 'package:objectbox/objectbox.dart';

@Entity()
class PrescriptionTemplate {
  @Id()
  int id = 0;

  String name; // e.g. "Cold & Fever", "Diabetes Follow-up"
  String diagnosis; // Pre-filled diagnosis
  String complaints; // Pre-filled chief complaints
  String notes; // Pre-filled doctor notes
  String itemsJson; // JSON array of PrescriptionItem (same format)
  String labTestsJson; // JSON array of test names

  // Optional: associate with a specific doctor
  int doctorId; // 0 = global template

  @Property(type: PropertyType.date)
  DateTime createdAt;

  PrescriptionTemplate({
    this.id = 0,
    required this.name,
    this.diagnosis = '',
    this.complaints = '',
    this.notes = '',
    this.itemsJson = '[]',
    this.labTestsJson = '[]',
    this.doctorId = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'diagnosis': diagnosis,
        'complaints': complaints,
        'notes': notes,
        'itemsJson': itemsJson,
        'labTestsJson': labTestsJson,
        'doctorId': doctorId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PrescriptionTemplate.fromJson(Map<String, dynamic> json) =>
      PrescriptionTemplate(
        id: json['id'] ?? 0,
        name: json['name'],
        diagnosis: json['diagnosis'] ?? '',
        complaints: json['complaints'] ?? '',
        notes: json['notes'] ?? '',
        itemsJson: json['itemsJson'] ?? '[]',
        labTestsJson: json['labTestsJson'] ?? '[]',
        doctorId: json['doctorId'] ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] ?? ''),
      );
}
