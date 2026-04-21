import 'package:objectbox/objectbox.dart';

@Entity()
class Patient {
  @Id()
  int id = 0;

  String uhid; // Auto-generated: OPD-DDMMYY-NNNN
  String name;
  String phone;
  String gender; // Male / Female / Other
  String address;
  String bloodGroup;

  int age;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  Patient({
    this.id = 0,
    required this.uhid,
    required this.name,
    this.phone = '',
    this.gender = 'Male',
    this.address = '',
    this.bloodGroup = '',
    this.age = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  int get ageYears => age;
}
