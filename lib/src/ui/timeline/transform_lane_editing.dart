// Per-lane key edits on a TransformTrack, keyed by the lane ids that
// transformPropertyLanes emits. Every function returns the edited track
// (or null when the edit is a no-op/invalid) — callers commit it as ONE
// undo step.

import '../../models/canvas_point.dart';
import '../../models/property_track.dart';
import '../../models/transform_track.dart';
import 'lane_span_keys_shift.dart';
import 'property_lane_lens.dart';
import 'scale_lane_form.dart';

/// Adds a key at [frameIndex] with the property's RESOLVED value there
/// (AE behavior: keying a property freezes its current value), or removes
/// the existing key — the keyframe-navigator diamond toggle.
/// [resolvedAnchorPoint]/[resolvedOpacity] feed the layer-only lanes (the
/// caller resolves them; a null anchor no-ops the anchor lane).
TransformTrack? transformTrackWithLaneKeyToggled(
  TransformTrack track, {
  required String laneId,
  required int frameIndex,
  required TransformPose resolvedPose,
  CanvasPoint? resolvedAnchorPoint,
  double resolvedOpacity = 1,
}) {
  if (frameIndex < 0) {
    return null;
  }
  switch (laneId) {
    case 'anchor-point':
      if (track.anchorPoint.keyAt(frameIndex) != null) {
        return track.copyWith(
          anchorPoint: track.anchorPoint.withoutKey(frameIndex),
        );
      }
      if (resolvedAnchorPoint == null) {
        return null;
      }
      return track.copyWith(
        anchorPoint: pathLaneKeyed(
          track.anchorPoint,
          frameIndex,
          resolvedAnchorPoint,
        ),
      );
    case 'position':
      return track.copyWith(
        position: track.position.keyAt(frameIndex) != null
            ? track.position.withoutKey(frameIndex)
            : pathLaneKeyed(
                track.position,
                frameIndex,
                resolvedPose.center,
              ),
      );
    case 'scale':
      return track.copyWith(
        scale: track.scale.keyAt(frameIndex) != null
            ? track.scale.withoutKey(frameIndex)
            : track.scale.withKey(frameIndex, resolvedPose.scale),
      );
    case 'rotation':
      return track.copyWith(
        rotation: track.rotation.keyAt(frameIndex) != null
            ? track.rotation.withoutKey(frameIndex)
            : track.rotation.withKey(frameIndex, resolvedPose.rotationDegrees),
      );
    case 'opacity':
      return track.copyWith(
        opacity: track.opacity.keyAt(frameIndex) != null
            ? track.opacity.withoutKey(frameIndex)
            : track.opacity.withKey(
                frameIndex,
                resolvedOpacity.clamp(0.0, 1.0).toDouble(),
              ),
      );
  }
  return null;
}

// 2026-08-08: `transformTrackWithLaneKeyMoved` (and its `_moved` helper)
// went with the key marker's private drag. Re-timing is
// [transformTrackWithLaneSpanKeysShifted] now — select the span, move the
// span — and a dead single-key mover left lying here is an invitation to
// wire the second grammar back.

/// The key window's write on lane [laneId] (F-17 · I-89): the keys inside
/// [frames] named as [naming] says (a null name un-names them) — all
/// collapsed onto ONE value, the key the name already holds on [adoptFrom]
/// where it holds one (this row's 겸용 sibling, or this very track) — and
/// then as [pick] leaves them: its path and its roving time on a lane
/// whose keys walk a path alone ([walksAPath]). ONE write of the lane
/// ([PropertyTrack.withKeysWritten]). Null when nothing changed.
///
/// The range form of naming — see [PropertyTrack.withRangeNamed] for why
/// the collapse is the intent rather than a side effect. The type it
/// writes replaced a per-key Toggle Hold that only the camera's own key
/// window ever called. That window is gone, and the common one says WHICH
/// type rather than flipping whichever it was.
TransformTrack? transformTrackWithLaneKeysWritten(
  TransformTrack track, {
  required String laneId,
  required Set<int> frames,
  ({String? name, int? preferredFrame})? naming,
  TransformTrack? adoptFrom,
  KeyTypePick pick = const KeyTypePick(),
}) {
  final property = transformPropertyOfLaneId(laneId);
  return transformLaneLens(laneId)?.keysWritten(
    track,
    frames: frames,
    naming: naming,
    adoptFrom: adoptFrom,
    pick: property != null && walksAPath(property) ? pick : pick.sidesAlone,
  );
}

/// Applies a value typed into a lane's value editor: sets/updates the key
/// at [frameIndex] (AE: changing an animated value keys it at the
/// playhead), preserving an existing key's sides. Accepted input
/// per lane (AE display units): position/anchor `x, y`; scale as the row's
/// [scaleForm] reads it — a camera's one zoom `150%`, a layer's two
/// `150, 80%`, the one left as shown carried when [scaleLinked]
/// ([ScaleLaneForm.typed]); rotation `45` or `45°`; opacity `75` or `75%`
/// (clamped 0–100). Null on parse failure.
///
/// [unkeyedScale] is what the Scale lane holds with no key — 1 on a layer,
/// and where a reference's fx placed its picture (F-374).
TransformTrack? transformTrackWithLaneValueEdited(
  TransformTrack track, {
  required String laneId,
  required int frameIndex,
  required String input,
  required ScaleLaneForm scaleForm,
  required bool scaleLinked,
  CanvasPoint? unkeyedScale,
}) {
  if (frameIndex < 0) {
    return null;
  }
  switch (laneId) {
    case 'anchor-point':
      final point = _parsePoint(input);
      if (point == null) {
        return null;
      }
      return track.copyWith(
        anchorPoint: pathLaneKeyed(track.anchorPoint, frameIndex, point),
      );
    case 'position':
      final point = _parsePoint(input);
      if (point == null) {
        return null;
      }
      return track.copyWith(
        position: pathLaneKeyed(track.position, frameIndex, point),
      );
    case 'scale':
      // What the lane shows at the frame is what the typed value is read
      // against — a link carries the box that was left as it was shown.
      final scale = scaleForm.typed(
        input,
        current: track.scale.resolveAt(
          frameIndex: frameIndex,
          orElse: () => unkeyedScale ?? uniformScale(1),
          space: pointKeySpace,
        ),
        linked: scaleLinked,
      );
      if (scale == null) {
        return null;
      }
      return track.copyWith(scale: track.scale.withKey(frameIndex, scale));
    case 'rotation':
      final degrees = _parseDegrees(input);
      if (degrees == null) {
        return null;
      }
      return track.copyWith(
        rotation: track.rotation.withKey(
          frameIndex,
          degrees,
        ),
      );
    case 'opacity':
      final percent = double.tryParse(input.replaceAll('%', '').trim());
      if (percent == null) {
        return null;
      }
      return track.copyWith(
        opacity: track.opacity.withKey(
          frameIndex,
          (percent / 100).clamp(0.0, 1.0).toDouble(),
        ),
      );
  }
  return null;
}

/// Applies the canvas Position gizmo's drag: keys the dragged position at
/// [frameIndex] (AE: changing an animated value keys it at the playhead),
/// preserving an existing key's interpolation — the same rule as the value
/// editor, minus the text form.
TransformTrack transformTrackWithPositionDragged(
  TransformTrack track, {
  required int frameIndex,
  required CanvasPoint position,
}) {
  return track.copyWith(
    position: pathLaneKeyed(track.position, frameIndex, position),
  );
}

/// A path's knob carried on the canvas (I-89 ④-Q4 A: 「캔버스에서 끈 접선 —
/// 반대쪽은 거울」): the key at [frameIndex] of lane [property] — one whose
/// keys walk a path ([walksAPath]) — bends along [tangent], how far the
/// knob stands from the key — its mirror behind it. The key's value, sides
/// and name stay as they are, and where no such key stands nothing
/// changes.
TransformTrack transformTrackWithPathHandle(
  TransformTrack track, {
  required TransformPropertyId property,
  required int frameIndex,
  required CanvasPoint tangent,
}) {
  final bent = transformPathLaneOf(
    track,
    property,
  )?.withKeyPath(frameIndex, HandledPath(tangent));
  if (bent == null) {
    return track;
  }
  return property == TransformPropertyId.anchorPoint
      ? track.copyWith(anchorPoint: bent)
      : track.copyWith(position: bent);
}

/// The transform box's SCALE release (R5 #10): ONE key at the playhead on
/// the scale lane alone. Dragging a corner is a statement about scale, so
/// nothing else keys. [scale] is the two the box reached — a camera's the
/// one zoom, twice.
TransformTrack transformTrackWithScaleDragged(
  TransformTrack track, {
  required int frameIndex,
  required CanvasPoint scale,
}) {
  return track.copyWith(scale: track.scale.withKey(frameIndex, scale));
}

/// The transform box's ROTATE release (R5 #10) — the rotation lane alone.
TransformTrack transformTrackWithRotationDragged(
  TransformTrack track, {
  required int frameIndex,
  required double rotationDegrees,
}) {
  return track.copyWith(
    rotation: track.rotation.withKey(
      frameIndex,
      rotationDegrees,
    ),
  );
}

/// The anchor gizmo's release (R5 #10): ONE key at the playhead, the twin
/// of [transformTrackWithPositionDragged]. The member you touch is the
/// member that keys — Position is not compensated.
TransformTrack transformTrackWithAnchorDragged(
  TransformTrack track, {
  required int frameIndex,
  required CanvasPoint anchorPoint,
}) {
  return track.copyWith(
    anchorPoint: pathLaneKeyed(track.anchorPoint, frameIndex, anchorPoint),
  );
}

// F-374: `poseWithLaneValueEdited` — a value typed into a reference fx's
// one pose — went when its lanes became keyed transform lanes. A reference
// lane's value is [transformTrackWithLaneValueEdited] on its fx now, and a
// second reader of the same three inputs is how the two would drift.

CanvasPoint? _parsePoint(String input) {
  final parts = input.split(',');
  if (parts.length != 2) {
    return null;
  }
  final x = double.tryParse(parts[0].trim());
  final y = double.tryParse(parts[1].trim());
  if (x == null || y == null) {
    return null;
  }
  return CanvasPoint(x: x, y: y);
}

double? _parseDegrees(String input) =>
    double.tryParse(input.replaceAll('°', '').trim());


/// AE's group Reset, for the Transform group (R5, user 2026-08-09).
///
/// The rule, in the user's words: **키를 삭제하진 않고 값만 리셋**. So this
/// never removes a key, and it never authors animation where there was
/// none — an EMPTY lane is already sitting at its default, and writing one
/// there would turn a static property into a keyed one behind the user's
/// back.
///
/// [frameIndexes] is the scope: the playhead alone, or the frames of the
/// keys a live lane-range selection covers. [keyedFramesOnly] is what tells
/// those two apart — resetting AT the playhead has to write a key on an
/// animated lane (that is the only way the value THERE can be the default),
/// while resetting a SELECTION means "reset the selected keys" and must not
/// invent one at every frame the band happens to cross.
///
/// Returns null when nothing changed.
TransformTrack? transformTrackWithGroupReset(
  TransformTrack track, {
  required Iterable<int> frameIndexes,
  required TransformPose identity,
  required CanvasPoint defaultAnchorPoint,
  bool keyedFramesOnly = false,
}) {
  final frames = frameIndexes.where((frame) => frame >= 0).toSet();
  if (frames.isEmpty) {
    return null;
  }

  PropertyTrack<T>? reset<T>(
    PropertyTrack<T> lane,
    T value, [
    PropertyTrack<T> Function(PropertyTrack<T> lane, int frame, T value)?
        keyed,
  ]) {
    // Untouched by design: no keys means the lane already resolves to its
    // default everywhere.
    if (lane.isEmpty) {
      return null;
    }
    var next = lane;
    for (final frame in frames) {
      if (keyedFramesOnly && lane.keyAt(frame) == null) {
        continue;
      }
      next = keyed?.call(next, frame, value) ?? next.withKey(frame, value);
    }
    return next == lane ? null : next;
  }

  final anchor = reset(track.anchorPoint, defaultAnchorPoint, pathLaneKeyed);
  final position = reset(track.position, identity.center, pathLaneKeyed);
  final scale = reset(track.scale, identity.scale);
  final rotation = reset(track.rotation, identity.rotationDegrees);
  final opacity = reset(track.opacity, 1.0);
  if (anchor == null &&
      position == null &&
      scale == null &&
      rotation == null &&
      opacity == null) {
    return null;
  }
  return track.copyWith(
    anchorPoint: anchor ?? track.anchorPoint,
    position: position ?? track.position,
    scale: scale ?? track.scale,
    rotation: rotation ?? track.rotation,
    opacity: opacity ?? track.opacity,
  );
}

/// The transform family's lane table: where each lane id lives on the
/// track. The single-lane range move is [LaneKeysShift.keysShifted] on
/// this table; null for an id that is not a transform lane.
PropertyLaneLens<TransformTrack, Object?>? transformLaneLens(String laneId) =>
    switch (laneId) {
      'anchor-point' => PropertyLaneLens<TransformTrack, CanvasPoint>(
        get: (track) => track.anchorPoint,
        set: (track, lane) => track.copyWith(anchorPoint: lane),
      ),
      'position' => PropertyLaneLens<TransformTrack, CanvasPoint>(
        get: (track) => track.position,
        set: (track, lane) => track.copyWith(position: lane),
      ),
      'scale' => PropertyLaneLens<TransformTrack, CanvasPoint>(
        get: (track) => track.scale,
        set: (track, lane) => track.copyWith(scale: lane),
      ),
      'rotation' => PropertyLaneLens<TransformTrack, double>(
        get: (track) => track.rotation,
        set: (track, lane) => track.copyWith(rotation: lane),
      ),
      'opacity' => PropertyLaneLens<TransformTrack, double>(
        get: (track) => track.opacity,
        set: (track, lane) => track.copyWith(opacity: lane),
      ),
      _ => null,
    };

/// Shifts every ranged key of EVERY [laneIds] lane by [frameDelta] —
/// the MULTI-LANE range move (R26 #3): rigid group, one delta,
/// all-or-nothing ACROSS lanes. A span lane with no key in the range
/// simply rides along; a lane whose landing is blocked (below 0 or onto
/// an unshifted key) vetoes the WHOLE move. Null when blocked or when no
/// lane moves a key.
TransformTrack? transformTrackWithLaneSpanKeysShifted(
  TransformTrack track, {
  required List<String> laneIds,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) => laneSpanKeysShifted(
  track,
  laneIds: laneIds,
  lensOf: transformLaneLens,
  rangeStartIndex: rangeStartIndex,
  rangeEndIndexExclusive: rangeEndIndexExclusive,
  frameDelta: frameDelta,
);

/// The lane's keyed frames — the keyframe navigator's ◀/▶ jump targets.
Set<int> transformLaneKeyFrames(TransformTrack track, String laneId) =>
    transformLaneLens(laneId)?.keyFrames(track) ?? const {};
