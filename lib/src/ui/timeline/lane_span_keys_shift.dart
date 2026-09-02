/// A track with every lane in [laneIds] shifted through [laneKeysShifted]
/// over the range, all-or-nothing ACROSS lanes: a lane with no key in the
/// range rides along; a lane whose landing is blocked vetoes the WHOLE
/// move. Null when blocked, when the delta is 0, or when no lane moves a
/// key.
///
/// 🚨ONE law for the transform track and the SE name-tag track. Each
/// carried this loop over its own lane functions (the audit's clone scan,
/// 2026-09-03); the loop is the law, the two functions are the material.
T? laneSpanKeysShifted<T>(
  T track, {
  required List<String> laneIds,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
  required Set<int> Function(T track, String laneId) laneKeyFrames,
  required T? Function(
    T track, {
    required String laneId,
    required int rangeStartIndex,
    required int rangeEndIndexExclusive,
    required int frameDelta,
  })
  laneKeysShifted,
}) {
  if (frameDelta == 0) {
    return null;
  }
  var current = track;
  var movedAny = false;
  for (final laneId in laneIds) {
    final hasRangedKey = laneKeyFrames(current, laneId).any(
      (frame) => frame >= rangeStartIndex && frame < rangeEndIndexExclusive,
    );
    if (!hasRangedKey) {
      continue; // Nothing of this lane in the range — it rides along.
    }
    final next = laneKeysShifted(
      current,
      laneId: laneId,
      rangeStartIndex: rangeStartIndex,
      rangeEndIndexExclusive: rangeEndIndexExclusive,
      frameDelta: frameDelta,
    );
    if (next == null) {
      return null; // This lane HAD keys, so null here means blocked.
    }
    current = next;
    movedAny = true;
  }
  return movedAny ? current : null;
}
