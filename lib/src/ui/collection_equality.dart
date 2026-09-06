import 'package:flutter/foundation.dart';

/// Whether [a] and [b] hold the same keys with element-wise equal lists.
///
/// `mapEquals` compares the LISTS by identity, which a rebuilt chain
/// never satisfies — the preview would then read as changed on every
/// step whose keys did not actually move.
bool mapOfListsEquals<K, V>(Map<K, List<V>>? a, Map<K, List<V>>? b) {
  if (a == null || b == null) {
    return a == b;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!listEquals(entry.value, b[entry.key])) {
      return false;
    }
  }
  return true;
}

/// An order-independent hash of [m]'s entries, consistent with `mapEquals`.
int mapHash<K, V>(Map<K, V>? m) => m == null
    ? null.hashCode
    : Object.hashAllUnordered(
        m.entries.map((e) => Object.hash(e.key, e.value)),
      );

/// An order-independent hash of [m]'s entries, consistent with
/// [mapOfListsEquals] — each list hashes by its elements, not its identity.
int mapOfListsHash<K, V>(Map<K, List<V>>? m) => m == null
    ? null.hashCode
    : Object.hashAllUnordered(
        m.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
      );
