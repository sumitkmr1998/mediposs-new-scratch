import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/services/login_rate_limiter.dart';

void main() {
  test('five failed logins block attempts until the window expires', () {
    final limiter = LoginRateLimiter();
    final start = DateTime(2026, 10, 2, 9);
    for (var i = 0; i < 5; i++) {
      expect(limiter.isBlocked('device:admin', start), isFalse);
      limiter.recordFailure('device:admin', start);
    }
    expect(limiter.isBlocked('device:admin', start), isTrue);
    expect(limiter.isBlocked('device:admin', start.add(const Duration(minutes: 15))),
        isFalse);
  });
}
