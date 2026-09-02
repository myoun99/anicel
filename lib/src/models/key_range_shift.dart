/// Keyed entries STARTING in [rangeStartIndex, rangeEndIndexExclusive)
/// shifted by [frameDelta], all-or-nothing (the block discipline: nothing
/// merges silently): null when nothing is in range, when the delta is 0,
/// when a landing dips below 0, or when a moved entry would overlap an
/// unmoved one — or one already landed. [extentOf] is how long an entry
/// is: 1 for a point key, its span for an event.
///
/// 🚨ONE law for the camera row's keyframes and the instruction rows'
/// event spans (UI-R20 #2, P3b-2). Each had its own copy of this walk,
/// differing only in the extent (the audit's clone scan, 2026-09-03).
Map<int, T>? shiftKeysInRange<T>({
  required Map<int, T> entries,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
  required int Function(T entry) extentOf,
}) {
  bool inRange(int frame) =>
      frame >= rangeStartIndex && frame < rangeEndIndexExclusive;
  final moved = <int>{
    for (final start in entries.keys)
      if (inRange(start)) start,
  };
  if (moved.isEmpty || frameDelta == 0) {
    return null;
  }
  final shifted = <int, T>{};
  for (final entry in entries.entries) {
    if (!moved.contains(entry.key)) {
      shifted[entry.key] = entry.value;
    }
  }
  for (final start in moved) {
    final entry = entries[start] as T;
    final landing = start + frameDelta;
    if (landing < 0) {
      return null;
    }
    final landingEnd = landing + extentOf(entry);
    for (final other in shifted.entries) {
      final otherEnd = other.key + extentOf(other.value);
      if (landing < otherEnd && other.key < landingEnd) {
        return null;
      }
    }
    shifted[landing] = entry;
  }
  return shifted;
}
