import 'dart:collection';

/// A sorted copy of [source] whose keys are frame indexes, refused when
/// any key is negative — the one law behind `Layer.timeline` and
/// `PropertyTrack.keys` (the round-8 audit, 2026-09-06: each constructor
/// had written the loop itself, differing only in the type argument and
/// the wording). [argumentName] and [indexNoun] are that wording:
/// `ArgumentError.value(key, argumentName, '$indexNoun indexes must be
/// non-negative.')`.
SplayTreeMap<int, V> nonNegativeIndexedCopy<V>(
  Map<int, V> source, {
  required String argumentName,
  required String indexNoun,
}) {
  final result = SplayTreeMap<int, V>();
  for (final entry in source.entries) {
    if (entry.key < 0) {
      throw ArgumentError.value(
        entry.key,
        argumentName,
        '$indexNoun indexes must be non-negative.',
      );
    }
    result[entry.key] = entry.value;
  }
  return result;
}
