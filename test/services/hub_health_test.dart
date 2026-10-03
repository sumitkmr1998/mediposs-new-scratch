import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/services/sync/hub_health.dart';

void main() {
  test('reads shop identity from the actual nested health envelope', () {
    final health = HubHealth.fromJson({
      'data': {
        'shopId': 'shop-a',
        'timestamp': '2026-10-03T01:00:00Z',
      }
    });
    expect(health.shopId, 'shop-a');
    expect(
        health.serverTime, DateTime.utc(2026, 10, 3, 1).millisecondsSinceEpoch);
  });
  test('supports flat legacy envelope and explicit server clock', () {
    final health = HubHealth.fromJson({'shopId': 'shop-a', 'serverTime': 100});
    expect(health.serverTime, 100);
  });
  test('missing identity cannot silently authorize pairing', () {
    expect(
        () => HubHealth.fromJson({
              'data': {'timestamp': '2026-10-03'}
            }),
        throwsFormatException);
  });
  test('missing server clock cannot advance checkpoint using client clock', () {
    expect(
        () => HubHealth.fromJson({
              'data': {'shopId': 'shop-a'}
            }),
        throwsFormatException);
  });
}
