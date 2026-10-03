import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/models/sync_queue_item.dart';

void main() {
  test('failed items wait before retry and quarantine after five attempts', () {
    final start = DateTime(2026, 10, 2, 9);
    final item = SyncQueueItem(entity: 'photo', action: 'create', dataJson: '{}');

    item.recordFailure('network:down', now: start);
    expect(item.retryCount, 1);
    expect(item.isReadyForRetry(start), isFalse);
    expect(item.isReadyForRetry(start.add(const Duration(minutes: 1))), isTrue);

    for (var i = 1; i < 5; i++) {
      item.recordFailure('network:down', now: start);
    }
    expect(item.isQuarantined, isTrue);
    expect(item.isReadyForRetry(start.add(const Duration(days: 1))), isFalse);

    item.resetRetry();
    expect(item.isReadyForRetry(start), isTrue);
  });

  test('legacy retry metadata remains eligible for a retry', () {
    final item = SyncQueueItem(
      entity: 'sale',
      action: 'create',
      dataJson: '{}',
      processingBy: 'retries:2:temporary_error',
    );
    expect(item.retryCount, 2);
    expect(item.isReadyForRetry(DateTime.now()), isTrue);
  });
}
