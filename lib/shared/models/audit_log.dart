import 'package:objectbox/objectbox.dart';

@Entity()
class AuditLog {
  @Id()
  int id = 0;

  String action;        // 'CREATE', 'UPDATE', 'DELETE', 'VOID', 'CANCEL', 'LOGIN'
  String entityType;    // 'Sale', 'Appointment', 'Medicine', 'Patient', 'AppUser'
  String entityId;      // ID or invoice code of target record
  String description;   // Human-readable summary of the action
  String detailsJson;   // JSON string containing detailed changes (before/after)
  String performedBy;   // Name & Role of the actor: e.g., "John (Pharmacist)"
  
  @Property(type: PropertyType.date)
  DateTime timestamp;

  String deviceId;
  bool isSynced;

  AuditLog({
    this.id = 0,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.description,
    this.detailsJson = '{}',
    required this.performedBy,
    required this.timestamp,
    required this.deviceId,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'description': description,
        'detailsJson': detailsJson,
        'performedBy': performedBy,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'deviceId': deviceId,
        'isSynced': isSynced,
      };

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        id: 0,
        action: json['action'] ?? '',
        entityType: json['entityType'] ?? '',
        entityId: json['entityId'] ?? '',
        description: json['description'] ?? '',
        detailsJson: json['detailsJson'] ?? '{}',
        performedBy: json['performedBy'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
        deviceId: json['deviceId'] ?? '',
        isSynced: true,
      );
}
