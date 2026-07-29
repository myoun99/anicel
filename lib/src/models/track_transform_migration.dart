import 'property_track.dart';
import 'transform_track.dart';

/// Migrates the legacy per-cut transform model (pre-`Track.transformTrack`
/// files) onto the track's GLOBAL frame axis — the SE lift's sibling
/// (track_se_migration.dart), for the V track's own effects.
///
/// Each cut's lane keys move by the cut's cumulative global start —
/// leading gaps included, matching the storyboard layout's frame axis;
/// keys at or past the cut's played window are dropped (they never showed
/// — `resolveAt` clamps at the window's ends, and the fade convention pins
/// its keys inside `[0, duration)`). Merged windows are disjoint by
/// construction, so keys can never collide.
///
/// Reads the RAW cut JSON maps rather than parsed cuts: the `Cut` model no
/// longer carries a transform at all (R4 — the track owns the effects),
/// so the legacy `'transform'` entries are lifted here and ignored
/// everywhere else.
TransformTrack liftCutTransformsToTrack(List<Map<String, dynamic>> cutsJson) {
  var merged = TransformTrack.empty();
  var nextStart = 0;
  for (final cutJson in cutsJson) {
    final duration = switch (cutJson['duration']) {
      final int value when value >= 1 => value,
      _ => 1,
    };
    final leadingGap = switch (cutJson['leadingGap']) {
      final int value when value >= 1 => value,
      _ => 0,
    };
    final start = nextStart + leadingGap;
    nextStart = start + duration;
    final transformJson = cutJson['transform'];
    if (transformJson is! Map<String, dynamic>) {
      continue;
    }
    final local = TransformTrack.fromJson(transformJson);
    merged = TransformTrack.properties(
      anchorPoint: _shifted(merged.anchorPoint, local.anchorPoint, start, duration),
      position: _shifted(merged.position, local.position, start, duration),
      scale: _shifted(merged.scale, local.scale, start, duration),
      rotation: _shifted(merged.rotation, local.rotation, start, duration),
      opacity: _shifted(merged.opacity, local.opacity, start, duration),
    );
  }
  return merged;
}

PropertyTrack<T> _shifted<T>(
  PropertyTrack<T> merged,
  PropertyTrack<T> local,
  int start,
  int duration,
) {
  var next = merged;
  local.keys.forEach((frame, key) {
    if (frame < 0 || frame >= duration) {
      return;
    }
    next = next.withKey(
      start + frame,
      key.value,
      interpolation: key.interpolation,
    );
  });
  return next;
}
