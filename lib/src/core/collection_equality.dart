/// Lightweight, dependency-free collection equality helpers for the pure-Dart
/// model layer.
///
/// These replace the many per-file `_listEquals` / `_mapEquals` copies that used
/// to be duplicated across model files. They intentionally avoid importing
/// `package:flutter/foundation.dart` so the model layer stays pure Dart and
/// JSON-friendly.
library;

/// Whether [a] and [b] match element for element under [match]: the same
/// length, and every pair at the same index matches.
///
/// ONE walk under [listEquals] and the two places that wrote it out again
/// on 2026-09-16 — the stack view's tree comparison (node for node) and
/// the tile pyramid's block identity (tile for tile, by `identical`) —
/// where the clone ratchet caught the copies.
bool listsMatch<T>(List<T> a, List<T> b, bool Function(T, T) match) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (!match(a[i], b[i])) return false;
  }
  return true;
}

/// Returns `true` when [a] and [b] have the same length and equal elements in
/// order, using each element's own `==`.
bool listEquals<T>(List<T> a, List<T> b) =>
    identical(a, b) || listsMatch(a, b, (x, y) => x == y);

/// Returns `true` when [a] and [b] hold the same elements, using each
/// element's own `==` through the sets' `contains`.
bool setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final element in a) {
    if (!b.contains(element)) return false;
  }
  return true;
}

/// Returns `true` when [a] and [b] have the same keys mapped to equal values,
/// using each value's own `==`.
bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
