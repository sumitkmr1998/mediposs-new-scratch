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

  int get retryCount {
    if (processingBy == null) return 0;
    if (processingBy!.startsWith('retries:')) {
      final parts = processingBy!.split(':');
      if (parts.length >= 2) {
        return int.tryParse(parts[1]) ?? 0;
      }
    }
    if (processingBy!.startsWith('quarantined:')) return 999;
    return 0;
  }

  bool get isQuarantined => processingBy?.startsWith('quarantined:') ?? false;

  void recordFailure(String reason) {
    final next = retryCount + 1;
    final sanitized = reason.replaceAll(':', '_');
    if (next >= 5) {
      processingBy = 'quarantined:$sanitized';
    } else {
      processingBy = 'retries:$next:$sanitized';
    }
  }

  void resetRetry() {
    processingBy = null;
  }
}

