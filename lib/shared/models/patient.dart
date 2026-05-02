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
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  int get ageYears => age;

  Map<String, dynamic> toJson() => {
        'id': id,
        'uhid': uhid,
        'name': name,
        'phone': phone,
        'gender': gender,
        'address': address,
        'bloodGroup': bloodGroup,
        'age': age,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] ?? 0,
        uhid: json['uhid'],
        name: json['name'],
        phone: json['phone'] ?? '',
        gender: json['gender'] ?? 'Male',
        address: json['address'] ?? '',
        bloodGroup: json['bloodGroup'] ?? '',
        age: json['age'] ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? ''),
      );
}
