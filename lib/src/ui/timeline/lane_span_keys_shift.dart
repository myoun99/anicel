import '../../models/property_track.dart';
import 'property_lane_lens.dart';

/// Shifts EVERY key of ONE lane inside [rangeStartIndex,
/// [rangeEndIndexExclusive]) by [frameDelta] — the lane-scoped range move
/// (UI-R23 #3 part 2): rigid group, one delta, all-or-nothing. Null when
/// nothing moves, a landing dips below 0, or a landing collides with an
/// UNSHIFTED key on the same lane (the block discipline: nothing merges
/// silently). Other lanes are untouched — the lane selection owns exactly
/// its own keys.
///
/// [lensOf] is the family's lane table (transform, SE name-tag, effect
/// chain); the verb itself is written once. The loop itself is the shared
/// law (transform/effect/name-tag families all shift through it):
/// [PropertyTrack.withRangedKeysShifted].
Track? trackWithLaneKeysShifted<Track>(
  Track track, {
  required LaneLens<Track>? Function(String laneId) lensOf,
  required String laneId,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  return lensOf(laneId)?.update(
    track,
    _rangedShift(
      rangeStartIndex: rangeStartIndex,
      rangeEndIndexExclusive: rangeEndIndexExclusive,
      frameDelta: frameDelta,
    ),
  );
}

PropertyLaneEdit _rangedShift({
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) =>
    <U>(PropertyTrack<U> lane) => lane.withRangedKeysShifted(
      rangeStartIndex: rangeStartIndex,
      rangeEndIndexExclusive: rangeEndIndexExclusive,
      frameDelta: frameDelta,
    );

/// A track with every lane in [laneIds] shifted through
/// [trackWithLaneKeysShifted]'s law over the range, all-or-nothing ACROSS
/// lanes: a lane with no key in the range rides along; a lane whose landing
/// is blocked vetoes the WHOLE move. Null when blocked, when the delta is
/// 0, or when no lane moves a key.
///
/// 🚨ONE law for the transform track and the SE name-tag track. Each
/// carried this loop over its own lane functions (the audit's clone scan,
/// 2026-09-03); the loop is the law, the family's lens table is the
/// material.
T? laneSpanKeysShifted<T>(
  T track, {
  required List<String> laneIds,
  required LaneLens<T>? Function(String laneId) lensOf,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  final shift = _rangedShift(
    rangeStartIndex: rangeStartIndex,
    rangeEndIndexExclusive: rangeEndIndexExclusive,
    frameDelta: frameDelta,
  );
  var current = track;
  var movedAny = false;
  for (final laneId in laneIds) {
    final lens = lensOf(laneId);
    final hasRangedKey =
        lens != null &&
        lens
            .keyFrames(current)
            .any(
              (frame) =>
                  frame >= rangeStartIndex && frame < rangeEndIndexExclusive,
            );
    if (!hasRangedKey) {
      continue; // Nothing of this lane in the range — it rides along.
    }
    final next = lens.update(current, shift);
    if (next == null) {
      return null; // This lane HAD keys, so null here means blocked.
    }
    current = next;
    movedAny = true;
  }
  return movedAny ? current : null;
}
