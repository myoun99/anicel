import '../../models/property_track.dart';

/// A verb on ONE lane, written without knowing the lane's value type: it
/// reads the lane and answers its replacement, or null for "nothing to
/// write". Every lane-scoped edit is this shape, so a verb is written once
/// and dispatched through a table instead of once per `switch (laneId)`
/// arm.
typedef PropertyLaneEdit = PropertyTrack<U>? Function<U>(PropertyTrack<U> lane);

/// Where a lane LIVES on its track — the address a verb dispatches over.
/// The property is data, the verb is written once (Blender's RNA property
/// paths, Krita's keyframe-channel lookups: the same shape).
///
/// 🚨The transform track and the SE name-tag track each carried a
/// `switch (laneId)` per VERB — seven arms and four — every arm reading one
/// field and writing it back through copyWith, and the two families'
/// keys-shift verbs were one algorithm over two such switches (the audit's
/// clone scan, round 8, 2026-09-06). This is that dispatch as a value: one
/// table per family, one entry per lane id, and the verbs stop knowing the
/// fields. A family whose lanes are not fields (the effect chain, addressed
/// by parsed (effectId, parameterId) over a list) implements the same two
/// answers its own way.
abstract interface class LaneLens<Track> {
  /// [track] with this lane replaced by what [edit] answers; null when
  /// [edit] answers null (nothing to write) or the lane cannot be reached.
  Track? update(Track track, PropertyLaneEdit edit);

  /// The lane's keyed frames — the keyframe navigator's ◀/▶ jump targets.
  Set<int> keyFrames(Track track);
}

/// A lane that is ONE [PropertyTrack] field of its track: read by [get],
/// written back by [set].
class PropertyLaneLens<Track, T> implements LaneLens<Track> {
  const PropertyLaneLens({required this.get, required this.set});

  final PropertyTrack<T> Function(Track track) get;
  final Track Function(Track track, PropertyTrack<T> lane) set;

  @override
  Track? update(Track track, PropertyLaneEdit edit) {
    final next = edit<T>(get(track));
    return next == null ? null : set(track, next);
  }

  @override
  Set<int> keyFrames(Track track) => get(track).keys.keys.toSet();
}
