import 'package:objectbox/objectbox.dart';

@Entity()
class PatientImage {
  @Id()
  int id = 0;

  int patientId;
  String imagePath; // Local path to the saved image
  String category; // e.g. "Progress", "X-Ray", "Report"

  @Property(type: PropertyType.date)
  DateTime date;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  PatientImage({
    this.id = 0,
    required this.patientId,
    required this.imagePath,
    this.category = 'General',
    DateTime? date,
    DateTime? createdAt,
  })  : date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();
}
