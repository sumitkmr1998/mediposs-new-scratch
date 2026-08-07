/// Helpers for merging remote sync payloads without full-table scans when possible.

/// Index local entities by a natural key for O(1) upsert.
Map<String, T> indexByKey<T>(
  Iterable<T> items,
  String Function(T item) keyOf,
) {
  final map = <String, T>{};
  for (final item in items) {
    final k = keyOf(item);
    if (k.isEmpty) continue;
    map[k] = item;
  }
  return map;
}

/// Prefer looking up only the keys present in [remoteKeys] via [findByKey].
/// Falls back to [loadAllLocal] when the remote set is large (cheaper than N queries).
Map<String, T> loadLocalsForKeys<T>({
  required Iterable<String> remoteKeys,
  required T? Function(String key) findByKey,
  required List<T> Function() loadAllLocal,
  required String Function(T item) keyOf,
  int queryThreshold = 40,
}) {
  final keys = remoteKeys.where((k) => k.isNotEmpty).toSet();
  if (keys.isEmpty) return {};

  if (keys.length > queryThreshold) {
    return indexByKey(loadAllLocal(), keyOf);
  }

  final map = <String, T>{};
  for (final k in keys) {
    final local = findByKey(k);
    if (local != null) map[k] = local;
  }
  return map;
}

/// Whether remote should overwrite local based on updatedAt.
bool remoteIsNewer(DateTime? remoteUpdated, DateTime? localUpdated) {
  if (remoteUpdated == null) return true;
  if (localUpdated == null) return true;
  return !remoteUpdated.isBefore(localUpdated);
}
