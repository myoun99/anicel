/// What a frame range holds of a keyed row: the [keys] STARTING in
/// [rangeStartIndex, rangeEndIndexExclusive) — the starts of a row's spans.
Set<int> keysStartingIn(
  Iterable<int> keys,
  int rangeStartIndex,
  int rangeEndIndexExclusive,
) => {
  for (final key in keys)
    if (key >= rangeStartIndex && key < rangeEndIndexExclusive) key,
};

/// The keyed [entries] STARTING at [moved] shifted by [frameDelta],
/// all-or-nothing (the block discipline: nothing merges silently): null
/// when nothing moves, when the delta is 0, when a landing dips below 0, or
/// when a moved entry would overlap an unmoved one — or one already landed.
/// [extentOf] is how long an entry is: its span, for an event.
///
/// [moved] is what a selection holds, which is not always a range of the
/// entries: a cut's transition marks map back to spans that start
/// elsewhere, and skip the ones the cut does not edit
/// (transition-row-range-in-the-cut).
///
/// ↩️It was ONE law for the camera row's keyframes and the instruction
/// rows' event spans (UI-R20 #2, P3b-2 — pulled out of their two copies by
/// the audit's clone scan, 2026-09-03), entered by a frame range
/// (`shiftKeysInRange`). A camera's keys are not the entries of one map:
/// each lane holds its own, and since F-309 they shift by the lanes' law
/// ([PropertyTrack.withRangedKeysShifted]) — moved as whole poses, they
/// came back keyed on lanes that had held no key. The range entry went
/// with its last caller.
Map<int, T>? shiftKeysAt<T>({
  required Map<int, T> entries,
  required Set<int> moved,
  required int frameDelta,
  required int Function(T entry) extentOf,
}) {
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
