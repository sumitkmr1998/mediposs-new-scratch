import '../../models/sync_queue_item.dart';

/// One finite, ordered pass. A network outage must never discard a mutation.
class OutboxDrain {
  static Future<bool> run({
    required List<SyncQueueItem> items,
    required Future<bool> Function(SyncQueueItem) push,
    required void Function(SyncQueueItem) save,
    required DateTime Function() now,
  }) async {
    var failed = false;
    for (final item in items) {
      if (item.processed) continue;
      final optional = item.entity == 'photo';
      if (!item.isReadyForRetry(now())) {
        failed = true;
        if (optional) continue;
        break;
      }
      try {
        if (await push(item)) {
          item.processed = true;
          item.resetRetry();
          save(item);
          continue;
        }
        item.recordTransientFailure('Upload not acknowledged', now: now());
      } on FormatException catch (e) {
        // Invalid payloads need repair, not repeated uploads or silent success.
        item.processingBy = 'quarantined:${e.message}';
      } catch (e) {
        item.recordTransientFailure(e.toString(), now: now());
      }
      save(item);
      failed = true;
      if (!optional) break;
    }
    return failed;
  }
}
