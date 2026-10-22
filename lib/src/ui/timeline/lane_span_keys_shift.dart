import '../../models/property_track.dart';
import 'property_lane_lens.dart';

/// The lane-scoped range move, as a verb on the lane's address.
extension LaneKeysShift<Track> on LaneLens<Track> {
  /// Moves EVERY key of this lane [move] takes — the lane-scoped range move
  /// (UI-R23 #3 part 2): rigid group, all-or-nothing. Null when nothing is
  /// in the range, a landing dips below 0, or a landing collides with a key
  /// not moved on the same lane (the block discipline: nothing merges
  /// silently). Other lanes are untouched — the lane selection owns exactly
  /// its own keys.
  ///
  /// Written once over the lens; each family's table (transform, SE
  /// name-tag, effect chain) resolves the lane id to the lens. The loop
  /// itself is the shared law (transform/effect/name-tag families all
  /// move through it): [PropertyTrack.withRangedKeysMoved].
  Track? keysMoved(Track track, LaneSpanMove move) => update(
    track,
    <U>(PropertyTrack<U> lane) => lane.withRangedKeysMoved(
      rangeStartIndex: move.rangeStartIndex,
      rangeEndIndexExclusive: move.rangeEndIndexExclusive,
      to: move.to,
    ),
  );
}

/// A track with every lane in [laneIds] shifted [frameDelta] frames over
/// the range, all-or-nothing ACROSS lanes ([laneSpanKeysMoved], every key
/// the same frames on). Null when blocked, or when no lane moves a key —
/// a delta of 0 moves none.
T? laneSpanKeysShifted<T>(
  T track, {
  required List<String> laneIds,
  required LaneLens<T>? Function(String laneId) lensOf,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) => laneSpanKeysMoved(
  track,
  laneIds: laneIds,
  lensOf: lensOf,
  move: (
    rangeStartIndex: rangeStartIndex,
    rangeEndIndexExclusive: rangeEndIndexExclusive,
    to: (frame) => frame + frameDelta,
  ),
);

/// Where a lane span's move takes its keys: those inside
/// [rangeStartIndex, [rangeEndIndexExclusive]), each to the frame [to]
/// gives it.
typedef LaneSpanMove = ({
  int rangeStartIndex,
  int rangeEndIndexExclusive,
  int Function(int frame) to,
});

/// A track with every lane in [laneIds] moved as [move] says through
/// [LaneKeysShift.keysMoved], all-or-nothing ACROSS lanes: a lane none of
/// whose keys [move] moves rides along; a lane whose landing is blocked
/// vetoes the WHOLE move. Null when blocked, or when no lane moves a key.
///
/// 🚨ONE law for the transform track and the SE name-tag track. Each
/// carried this loop over its own lane functions (the audit's clone scan,
/// 2026-09-03); the loop is the law, the family's lens table is the
/// material.
T? laneSpanKeysMoved<T>(
  T track, {
  required List<String> laneIds,
  required LaneLens<T>? Function(String laneId) lensOf,
  required LaneSpanMove move,
}) {
  final (:rangeStartIndex, :rangeEndIndexExclusive, :to) = move;
  var current = track;
  var movedAny = false;
  for (final laneId in laneIds) {
    final lens = lensOf(laneId);
    final movesAKey =
        lens != null &&
        lens
            .keyFrames(current)
            .any(
              (frame) =>
                  frame >= rangeStartIndex &&
                  frame < rangeEndIndexExclusive &&
                  to(frame) != frame,
            );
    if (!movesAKey) {
      continue; // Nothing of this lane moves — it rides along.
    }
    final next = lens.keysMoved(current, move);
    if (next == null) {
      return null; // This lane HAD keys to move, so null means blocked.
    }
    current = next;
    movedAny = true;
  }
  return movedAny ? current : null;
}
