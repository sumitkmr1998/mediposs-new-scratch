import 'package:objectbox/objectbox.dart';

@Entity()
class AttendanceRecord {
  @Id()
  int id = 0;

  int userId;
  String userName;

  @Property(type: PropertyType.date)
  DateTime checkIn;

  String date; // Format: YYYY-MM-DD
  String status; // 'present' or 'absent'

  AttendanceRecord({
    this.id = 0,
    required this.userId,
    required this.userName,
    required this.checkIn,
    required this.date,
    this.status = 'present',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'checkIn': checkIn.toIso8601String(),
        'date': date,
        'status': status,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        id: json['id'] ?? 0,
        userId: json['userId'],
        userName: json['userName'],
        checkIn: DateTime.parse(json['checkIn']),
        date: json['date'],
        status: json['status'] ?? 'present',
      );
}
