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

  DateTime? get nextRetryAt {
    final parts = processingBy?.split(':');
    if (parts == null || parts.length < 3 || parts.first != 'retries') {
      return null;
    }
    final millis = int.tryParse(parts[2]);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  bool isReadyForRetry(DateTime now) =>
      !isQuarantined && (nextRetryAt?.isAfter(now) != true);

  void recordFailure(String reason, {DateTime? now}) {
    final next = retryCount + 1;
    final sanitized = reason.replaceAll(':', '_');
    if (next >= 5) {
      processingBy = 'quarantined:$sanitized';
    } else {
      final delay = Duration(minutes: 1 << (next - 1));
      final retryAt = (now ?? DateTime.now()).add(delay).millisecondsSinceEpoch;
      processingBy = 'retries:$next:$retryAt:$sanitized';
    }
  }

  void resetRetry() {
    processingBy = null;
  }

  /// Unavailability has no retry limit: retain the mutation until acknowledged.
  void recordTransientFailure(String reason, {DateTime? now}) {
    final next = (retryCount + 1).clamp(1, 10);
    final delay = Duration(minutes: 1 << (next - 1).clamp(0, 5));
    final retryAt = (now ?? DateTime.now()).add(delay).millisecondsSinceEpoch;
    processingBy = 'retries:$next:$retryAt:${reason.replaceAll(':', '_')}';
  }
}

