import 'package:objectbox/objectbox.dart';
import 'dart:convert';

@Entity()
class SyncQueueItem {
  @Id()
  int id = 0;

  String entity; // "medicine", "patient", "sale", etc.
  String action; // "create", "update", "delete", "delta"
  String dataJson; // Serialized data or delta information
  
  @Property(type: PropertyType.date)
  DateTime timestamp;
  
  bool processed; // Locally processed by Hub?
  String? processingBy; // "hub_id" for transactional lease

  SyncQueueItem({
    this.id = 0,
    required this.entity,
    required this.action,
    required this.dataJson,
    DateTime? timestamp,
    this.processed = false,
    this.processingBy,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> get data => jsonDecode(dataJson);
}
