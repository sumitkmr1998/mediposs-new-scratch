import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/models/sync_queue_item.dart';
import 'package:medipos/shared/services/sync/outbox_drain.dart';

void main() {
  final start = DateTime(2026, 10, 3);
  SyncQueueItem item(String entity) =>
      SyncQueueItem(entity: entity, action: 'create', dataJson: '{}');

  test('quarantined-only outbox terminates and reports blocked', () async {
    final row = item('sale')..processingBy = 'quarantined:invalid';
    var attempts = 0;
    expect(
        await OutboxDrain.run(
            items: [row],
            push: (_) async {
              attempts++;
              return true;
            },
            save: (_) {},
            now: () => start).timeout(const Duration(seconds: 1)),
        isTrue);
    expect(attempts, 0);
    expect(row.processed, isFalse);
  });

  test('failed photo is attempted once and later sale proceeds', () async {
    final photo = item('photo');
    final sale = item('sale');
    final attempts = <String>[];
    expect(
        await OutboxDrain.run(
            items: [photo, sale],
            push: (row) async {
              attempts.add(row.entity);
              return row.entity != 'photo';
            },
            save: (_) {},
            now: () => start),
        isTrue);
    expect(attempts, ['photo', 'sale']);
    expect(photo.processed, isFalse);
    expect(photo.nextRetryAt, start.add(const Duration(minutes: 1)));
    expect(sale.processed, isTrue);
  });

  test('long outage retains sale and stops dependent writes', () async {
    final sale = item('sale');
    final dependent = item('patient');
    var clock = start;
    var attempts = 0;
    for (var i = 0; i < 30; i++) {
      await OutboxDrain.run(
          items: [sale, dependent],
          push: (_) async {
            attempts++;
            return false;
          },
          save: (_) {},
          now: () => clock);
      clock = sale.nextRetryAt!;
    }
    expect(attempts, 30);
    expect(sale.processed, isFalse);
    expect(sale.isQuarantined, isFalse);
    expect(dependent.retryCount, 0);
    expect(
        await OutboxDrain.run(
            items: [sale, dependent],
            push: (_) async => true,
            save: (_) {},
            now: () => clock),
        isFalse);
    expect(sale.processed && dependent.processed, isTrue);
  });

  test('retry delay prevents repeated UI-triggered uploads', () async {
    final sale = item('sale')..recordTransientFailure('offline', now: start);
    var attempts = 0;
    await OutboxDrain.run(
        items: [sale],
        push: (_) async {
          attempts++;
          return true;
        },
        save: (_) {},
        now: () => start);
    expect(attempts, 0);
  });

  test('failed audit remains pending and blocks later changes', () async {
    final audit = item('audit_log');
    final sale = item('sale');
    await OutboxDrain.run(
        items: [audit, sale],
        push: (_) async => false,
        save: (_) {},
        now: () => start);
    expect(audit.processed, isFalse);
    expect(sale.processed, isFalse);
  });

  test('bad payload is preserved for repair and never acknowledged', () async {
    final sale = item('sale');
    await OutboxDrain.run(
        items: [sale],
        push: (_) async {
          throw const FormatException('Invalid JSON');
        },
        save: (_) {},
        now: () => start);
    expect(sale.isQuarantined, isTrue);
    expect(sale.processed, isFalse);
  });

  test('transport exception retains mutation without quarantine', () async {
    final sale = item('sale');
    await OutboxDrain.run(
        items: [sale],
        push: (_) async {
          throw TimeoutException('Lost ACK');
        },
        save: (_) {},
        now: () => start);
    expect(sale.retryCount, 1);
    expect(sale.isQuarantined, isFalse);
    expect(sale.processed, isFalse);
  });
}
