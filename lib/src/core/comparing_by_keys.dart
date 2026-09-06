/// A comparator over an ordered tuple of comparable fields — Python's
/// `key=`, Java's `Comparator.comparing(…).thenComparing(…)`, C++'s
/// `std::tie` compared lexicographically.
///
/// The first key that differs decides; equal key lists compare as 0. The
/// ORDER of the keys is the only per-type knowledge, and it stays at the
/// sort site, where the reader can see it.
library;

Comparator<T> comparingByKeys<T>(
  List<Comparable<Object>> Function(T item) keysOf,
) {
  return (a, b) {
    final keysOfA = keysOf(a);
    final keysOfB = keysOf(b);
    assert(keysOfA.length == keysOfB.length, 'one key list per type');
    for (var i = 0; i < keysOfA.length; i += 1) {
      final comparison = keysOfA[i].compareTo(keysOfB[i]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  };
}
