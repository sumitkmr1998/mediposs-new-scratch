class LoginRateLimiter {
  LoginRateLimiter({this.maxFailures = 5, this.window = const Duration(minutes: 15)});

  final int maxFailures;
  final Duration window;
  final Map<String, List<DateTime>> _failures = {};

  bool isBlocked(String key, DateTime now) {
    final recent = _failures[key];
    if (recent == null) return false;
    recent.removeWhere((time) => now.difference(time) >= window);
    if (recent.isEmpty) _failures.remove(key);
    return recent.length >= maxFailures;
  }

  void recordFailure(String key, DateTime now) {
    isBlocked(key, now);
    _failures.putIfAbsent(key, () => []).add(now);
  }

  void recordSuccess(String key) => _failures.remove(key);
}
