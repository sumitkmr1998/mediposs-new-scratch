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
}
