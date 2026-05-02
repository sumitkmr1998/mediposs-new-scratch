import 'package:objectbox/objectbox.dart';

@Entity()
class Doctor {
  @Id()
  int id = 0;

  String name;
  String specialization; // e.g. General, Ortho, Gynae
  double consultationFee;
  String qualifications; // e.g. MBBS, MD
  String phone;
  bool isActive;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  Doctor({
    this.id = 0,
    required this.name,
    this.specialization = 'General',
    this.consultationFee = 0,
    this.qualifications = '',
    this.phone = '',
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'specialization': specialization,
        'consultationFee': consultationFee,
        'qualifications': qualifications,
        'phone': phone,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'] ?? 0,
        name: json['name'],
        specialization: json['specialization'] ?? 'General',
        consultationFee: (json['consultationFee'] as num?)?.toDouble() ?? 0,
        qualifications: json['qualifications'] ?? '',
        phone: json['phone'] ?? '',
        isActive: json['isActive'] ?? true,
        createdAt: DateTime.tryParse(json['createdAt'] ?? ''),
      );
}
