import 'package:objectbox/objectbox.dart';
import '../utils/date_helper.dart';

@Entity()
class Procedure {
  @Id()
  int id = 0;

  String name;
  String category;
  double basePrice;
  String description;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool synced;

  Procedure({
    this.id = 0,
    required this.name,
    this.category = 'Cosmetic',
    this.basePrice = 0.0,
    this.description = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.synced = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'basePrice': basePrice,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'synced': synced,
      };

  factory Procedure.fromJson(Map<String, dynamic> json) => Procedure(
        id: json['id'] ?? 0,
        name: json['name'],
        category: json['category'] ?? 'Cosmetic',
        basePrice: (json['basePrice'] as num).toDouble(),
        description: json['description'] ?? '',
        createdAt: DateHelper.parseDateTime(json['createdAt']),
        updatedAt: DateHelper.parseDateTime(json['updatedAt']),
        synced: json['synced'] ?? false,
      );
}

@Entity()
class ProcedureRecord {
  @Id()
  int id = 0;

  int procedureId;
  String procedureName; // Denormalized

  int patientId;
  String patientName; // Denormalized

  int doctorId;
  String doctorName; // Denormalized

  @Property(type: PropertyType.date)
  DateTime date;

  String notes;
  String settingsJson; // JSON: { "fluence": "10J", "spotSize": "4mm", etc. }
  String imagesJson;   // List<String>: paths to pre/post photos
  
  double priceCharged;
  String invoiceNo; // Link to Sale

  @Property(type: PropertyType.date)
  DateTime createdAt;

  bool synced;

  ProcedureRecord({
    this.id = 0,
    required this.procedureId,
    required this.procedureName,
    required this.patientId,
    required this.patientName,
    this.doctorId = 0,
    this.doctorName = '',
    DateTime? date,
    this.notes = '',
    this.settingsJson = '{}',
    this.imagesJson = '[]',
    this.priceCharged = 0.0,
    this.invoiceNo = '',
    DateTime? createdAt,
    this.synced = false,
  })  : date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'procedureId': procedureId,
        'procedureName': procedureName,
        'patientId': patientId,
        'patientName': patientName,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'date': date.toIso8601String(),
        'notes': notes,
        'settingsJson': settingsJson,
        'imagesJson': imagesJson,
        'priceCharged': priceCharged,
        'invoiceNo': invoiceNo,
        'createdAt': createdAt.toIso8601String(),
        'synced': synced,
      };

  factory ProcedureRecord.fromJson(Map<String, dynamic> json) => ProcedureRecord(
        id: json['id'] ?? 0,
        procedureId: json['procedureId'],
        procedureName: json['procedureName'],
        patientId: json['patientId'],
        patientName: json['patientName'],
        doctorId: json['doctorId'] ?? 0,
        doctorName: json['doctorName'] ?? '',
        date: DateHelper.parseDateTime(json['date']),
        notes: json['notes'] ?? '',
        settingsJson: json['settingsJson'] ?? '{}',
        imagesJson: json['imagesJson'] ?? '[]',
        priceCharged: (json['priceCharged'] as num).toDouble(),
        invoiceNo: json['invoiceNo'] ?? '',
        createdAt: DateHelper.parseDateTime(json['createdAt']),
        synced: json['synced'] ?? false,
      );
}
