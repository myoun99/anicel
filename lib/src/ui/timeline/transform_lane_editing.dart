// Per-lane key edits on a TransformTrack, keyed by the lane ids that
// transformPropertyLanes emits. Every function returns the edited track
// (or null when the edit is a no-op/invalid) — callers commit it as ONE
// undo step.

import '../../models/canvas_point.dart';
import '../../models/property_track.dart';
import '../../models/transform_track.dart';

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
        anchorPoint: track.anchorPoint.withKey(frameIndex, resolvedAnchorPoint),
      );
    case 'position':
      return track.copyWith(
        position: track.position.keyAt(frameIndex) != null
            ? track.position.withoutKey(frameIndex)
            : track.position.withKey(frameIndex, resolvedPose.center),
      );
    case 'scale':
      return track.copyWith(
        scale: track.scale.keyAt(frameIndex) != null
            ? track.scale.withoutKey(frameIndex)
            : track.scale.withKey(frameIndex, resolvedPose.zoom),
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

/// Removes a lane's key at [frameIndex].
TransformTrack? transformTrackWithLaneKeyRemoved(
  TransformTrack track, {
  required String laneId,
  required int frameIndex,
}) {
  switch (laneId) {
    case 'anchor-point':
      if (track.anchorPoint.keyAt(frameIndex) == null) return null;
      return track.copyWith(
        anchorPoint: track.anchorPoint.withoutKey(frameIndex),
      );
    case 'position':
      if (track.position.keyAt(frameIndex) == null) return null;
      return track.copyWith(position: track.position.withoutKey(frameIndex));
    case 'scale':
      if (track.scale.keyAt(frameIndex) == null) return null;
      return track.copyWith(scale: track.scale.withoutKey(frameIndex));
    case 'rotation':
      if (track.rotation.keyAt(frameIndex) == null) return null;
      return track.copyWith(rotation: track.rotation.withoutKey(frameIndex));
    case 'opacity':
      if (track.opacity.keyAt(frameIndex) == null) return null;
      return track.copyWith(opacity: track.opacity.withoutKey(frameIndex));
  }
  return null;
}

/// [track] with lane [laneId]'s keys inside [frames] named [name] (null
/// un-names them), all collapsed onto ONE value. Null when nothing changed.
///
/// The range form of naming — see [PropertyTrack.withRangeNamed] for why
/// the collapse is the intent rather than a side effect. [adoptFrom]
/// supplies the value when the name is already held elsewhere in the
/// naming space (this row's 겸용 sibling, or this very track).
TransformTrack? transformTrackWithLaneRangeNamed(
  TransformTrack track, {
  required String laneId,
  required Set<int> frames,
  required String? name,
  TransformTrack? adoptFrom,
  int? preferredFrame,
}) {
  T? held<T>(PropertyTrack<T> Function(TransformTrack) lane) {
    if (name == null || adoptFrom == null) {
      return null;
    }
    return lane(adoptFrom).valueForName(name);
  }

  switch (laneId) {
    case 'anchor-point':
      final lane = track.anchorPoint.withRangeNamed(
        frames: frames,
        name: name,
        adopted: held((t) => t.anchorPoint),
        preferredFrame: preferredFrame,
      );
      return lane == null ? null : track.copyWith(anchorPoint: lane);
    case 'position':
      final lane = track.position.withRangeNamed(
        frames: frames,
        name: name,
        adopted: held((t) => t.position),
        preferredFrame: preferredFrame,
      );
      return lane == null ? null : track.copyWith(position: lane);
    case 'scale':
      final lane = track.scale.withRangeNamed(
        frames: frames,
        name: name,
        adopted: held((t) => t.scale),
        preferredFrame: preferredFrame,
      );
      return lane == null ? null : track.copyWith(scale: lane);
    case 'rotation':
      final lane = track.rotation.withRangeNamed(
        frames: frames,
        name: name,
        adopted: held((t) => t.rotation),
        preferredFrame: preferredFrame,
      );
      return lane == null ? null : track.copyWith(rotation: lane);
    case 'opacity':
      final lane = track.opacity.withRangeNamed(
        frames: frames,
        name: name,
        adopted: held((t) => t.opacity),
        preferredFrame: preferredFrame,
      );
      return lane == null ? null : track.copyWith(opacity: lane);
  }
  return null;
}

/// Flips a key between linear and HOLD interpolation (AE's Toggle Hold
/// Keyframe).
TransformTrack? transformTrackWithLaneHoldToggled(
  TransformTrack track, {
  required String laneId,
  required int frameIndex,
}) {
  switch (laneId) {
    case 'anchor-point':
      final next = _holdToggled(track.anchorPoint, frameIndex);
      return next == null ? null : track.copyWith(anchorPoint: next);
    case 'position':
      final next = _holdToggled(track.position, frameIndex);
      return next == null ? null : track.copyWith(position: next);
    case 'scale':
      final next = _holdToggled(track.scale, frameIndex);
      return next == null ? null : track.copyWith(scale: next);
    case 'rotation':
      final next = _holdToggled(track.rotation, frameIndex);
      return next == null ? null : track.copyWith(rotation: next);
    case 'opacity':
      final next = _holdToggled(track.opacity, frameIndex);
      return next == null ? null : track.copyWith(opacity: next);
  }
  return null;
}

/// Applies a value typed into a lane's value editor: sets/updates the key
/// at [frameIndex] (AE: changing an animated value keys it at the
/// playhead), preserving an existing key's interpolation. Accepted input
/// per lane (AE display units): position/anchor `x, y`; scale `150` or
/// `150%` (zoom·100); rotation `45` or `45°`; opacity `75` or `75%`
/// (clamped 0–100). Null on parse failure.
TransformTrack? transformTrackWithLaneValueEdited(
  TransformTrack track, {
  required String laneId,
  required int frameIndex,
  required String input,
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
        anchorPoint: track.anchorPoint.withKey(
          frameIndex,
          point,
          interpolation: _keptInterpolation(track.anchorPoint, frameIndex),
        ),
      );
    case 'position':
      final point = _parsePoint(input);
      if (point == null) {
        return null;
      }
      return track.copyWith(
        position: track.position.withKey(
          frameIndex,
          point,
          interpolation: _keptInterpolation(track.position, frameIndex),
        ),
      );
    case 'scale':
      final percent = double.tryParse(input.replaceAll('%', '').trim());
      if (percent == null || percent <= 0) {
        return null;
      }
      return track.copyWith(
        scale: track.scale.withKey(
          frameIndex,
          percent / 100,
          interpolation: _keptInterpolation(track.scale, frameIndex),
        ),
      );
    case 'rotation':
      final degrees = double.tryParse(input.replaceAll('°', '').trim());
      if (degrees == null) {
        return null;
      }
      return track.copyWith(
        rotation: track.rotation.withKey(
          frameIndex,
          degrees,
          interpolation: _keptInterpolation(track.rotation, frameIndex),
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
          interpolation: _keptInterpolation(track.opacity, frameIndex),
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
    position: track.position.withKey(
      frameIndex,
      position,
      interpolation: _keptInterpolation(track.position, frameIndex),
    ),
  );
}

/// The transform box's SCALE release (R5 #10): ONE key at the playhead on
/// the scale lane alone. Dragging a corner is a statement about scale, so
/// nothing else keys.
TransformTrack transformTrackWithScaleDragged(
  TransformTrack track, {
  required int frameIndex,
  required double zoom,
}) {
  return track.copyWith(
    scale: track.scale.withKey(
      frameIndex,
      zoom,
      interpolation: _keptInterpolation(track.scale, frameIndex),
    ),
  );
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
      interpolation: _keptInterpolation(track.rotation, frameIndex),
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
    anchorPoint: track.anchorPoint.withKey(
      frameIndex,
      anchorPoint,
      interpolation: _keptInterpolation(track.anchorPoint, frameIndex),
    ),
  );
}

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

PropertyKeyInterpolation _keptInterpolation<T>(
  PropertyTrack<T> lane,
  int frameIndex,
) {
  return lane.keyAt(frameIndex)?.interpolation ??
      PropertyKeyInterpolation.linear;
}

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
  double defaultOpacity = 1,
  bool keyedFramesOnly = false,
}) {
  final frames = frameIndexes.where((frame) => frame >= 0).toSet();
  if (frames.isEmpty) {
    return null;
  }

  PropertyTrack<T>? reset<T>(PropertyTrack<T> lane, T value) {
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
      next = next.withKey(
        frame,
        value,
        interpolation: _keptInterpolation(lane, frame),
      );
    }
    return next == lane ? null : next;
  }

  final anchor = reset(track.anchorPoint, defaultAnchorPoint);
  final position = reset(track.position, identity.center);
  final scale = reset(track.scale, identity.zoom);
  final rotation = reset(track.rotation, identity.rotationDegrees);
  final opacity = reset(track.opacity, defaultOpacity);
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

/// Shifts EVERY key of ONE lane inside [rangeStartIndex,
/// [rangeEndIndexExclusive]) by [frameDelta] — the lane-scoped range move
/// (UI-R23 #3 part 2): rigid group, one delta, all-or-nothing. Null when
/// nothing moves, a landing dips below 0, or a landing collides with an
/// UNSHIFTED key on the same lane (the block discipline: nothing merges
/// silently). Other lanes are untouched — the lane selection owns exactly
/// its own keys.
TransformTrack? transformTrackWithLaneKeysShifted(
  TransformTrack track, {
  required String laneId,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  // The loop itself is the shared law (transform/effect/name-tag families
  // all shift through it).
  PropertyTrack<T>? shifted<T>(PropertyTrack<T> lane) =>
      lane.withRangedKeysShifted(
        rangeStartIndex: rangeStartIndex,
        rangeEndIndexExclusive: rangeEndIndexExclusive,
        frameDelta: frameDelta,
      );

  switch (laneId) {
    case 'anchor-point':
      final next = shifted(track.anchorPoint);
      return next == null ? null : track.copyWith(anchorPoint: next);
    case 'position':
      final next = shifted(track.position);
      return next == null ? null : track.copyWith(position: next);
    case 'scale':
      final next = shifted(track.scale);
      return next == null ? null : track.copyWith(scale: next);
    case 'rotation':
      final next = shifted(track.rotation);
      return next == null ? null : track.copyWith(rotation: next);
    case 'opacity':
      final next = shifted(track.opacity);
      return next == null ? null : track.copyWith(opacity: next);
  }
  return null;
}

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
}) {
  if (frameDelta == 0) {
    return null;
  }
  var current = track;
  var movedAny = false;
  for (final laneId in laneIds) {
    final hasRangedKey = transformLaneKeyFrames(current, laneId).any(
      (frame) => frame >= rangeStartIndex && frame < rangeEndIndexExclusive,
    );
    if (!hasRangedKey) {
      continue; // Nothing of this lane in the range — it rides along.
    }
    final next = transformTrackWithLaneKeysShifted(
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

/// The lane's keyed frames — the keyframe navigator's ◀/▶ jump targets.
Set<int> transformLaneKeyFrames(TransformTrack track, String laneId) {
  return switch (laneId) {
    'anchor-point' => track.anchorPoint.keys.keys.toSet(),
    'position' => track.position.keys.keys.toSet(),
    'scale' => track.scale.keys.keys.toSet(),
    'rotation' => track.rotation.keys.keys.toSet(),
    'opacity' => track.opacity.keys.keys.toSet(),
    _ => const {},
  };
}

PropertyTrack<T>? _holdToggled<T>(PropertyTrack<T> lane, int frameIndex) {
  final key = lane.keyAt(frameIndex);
  if (key == null) {
    return null;
  }
  return lane.withKey(
    frameIndex,
    key.value,
    interpolation: key.interpolation == PropertyKeyInterpolation.hold
        ? PropertyKeyInterpolation.linear
        : PropertyKeyInterpolation.hold,
  );
}
