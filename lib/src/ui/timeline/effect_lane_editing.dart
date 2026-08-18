// Per-lane key edits on a layer's EFFECT CHAIN, keyed by the lane ids
// [effectPropertyLanes] emits. Every function returns the edited chain (or
// null when the edit is a no-op / not an effect lane) — callers commit it as
// ONE undo step, exactly like the transform-lane helpers next door.
//
// The chain is a LIST, so each edit finds its effect by id, rebuilds that one
// entry and leaves the rest identical.

import '../../models/layer_effect.dart';
import '../../models/property_track.dart';
import 'effect_lane_policy.dart';

/// Adds a key at [frameIndex] holding the parameter's RESOLVED value there
/// (AE behaviour: keying a property freezes its current value), or removes
/// the existing one — the keyframe navigator's diamond toggle.
List<LayerEffect>? effectsWithLaneKeyToggled(
  List<LayerEffect> effects, {
  required String laneId,
  required int frameIndex,
}) {
  if (frameIndex < 0) {
    return null;
  }
  return _editParameter(effects, laneId, (parameter, spec) {
    if (parameter.track.keyAt(frameIndex) != null) {
      return parameter.copyWith(track: parameter.track.withoutKey(frameIndex));
    }
    return parameter.copyWith(
      track: parameter.track.withKey(
        frameIndex,
        spec.clamp(parameter.resolveAt(frameIndex)),
      ),
    );
  });
}

// 2026-08-08: `effectsWithLaneKeyMoved` went with the key marker's private
// drag. Re-timing is [effectsWithLaneSpanKeysShifted] now — select the
// span, move the span — and a dead single-key mover left lying here is an
// invitation to wire the second grammar back.

List<LayerEffect>? effectsWithLaneKeyRemoved(
  List<LayerEffect> effects, {
  required String laneId,
  required int frameIndex,
}) {
  return _editParameter(effects, laneId, (parameter, spec) {
    if (parameter.track.keyAt(frameIndex) == null) {
      return null;
    }
    return parameter.copyWith(track: parameter.track.withoutKey(frameIndex));
  });
}

/// [effects] with parameter lane [laneId]'s keys inside [frames] named
/// [name] (null un-names them), all collapsed onto ONE value. Null when
/// nothing changed.
///
/// The range form of naming — see [PropertyTrack.withRangeNamed] for why
/// the collapse is the intent rather than a side effect. [adopted] supplies
/// the value when the name is already held elsewhere in the naming space.
List<LayerEffect>? effectsWithLaneRangeNamed(
  List<LayerEffect> effects, {
  required String laneId,
  required Set<int> frames,
  required String? name,
  double? adopted,
  int? preferredFrame,
}) {
  return _editParameter(effects, laneId, (parameter, spec) {
    final track = parameter.track.withRangeNamed(
      frames: frames,
      name: name,
      adopted: adopted,
      preferredFrame: preferredFrame,
    );
    return track == null ? null : parameter.copyWith(track: track);
  });
}

/// Flips a key between linear and HOLD interpolation (AE's Toggle Hold
/// Keyframe).
List<LayerEffect>? effectsWithLaneHoldToggled(
  List<LayerEffect> effects, {
  required String laneId,
  required int frameIndex,
}) {
  return _editParameter(effects, laneId, (parameter, spec) {
    final key = parameter.track.keyAt(frameIndex);
    if (key == null) {
      return null;
    }
    return parameter.copyWith(
      track: parameter.track.withKey(
        frameIndex,
        key.value,
        interpolation: key.interpolation == PropertyKeyInterpolation.hold
            ? PropertyKeyInterpolation.linear
            : PropertyKeyInterpolation.hold,
      ),
    );
  });
}

/// Applies a value typed into a lane's value editor.
///
/// Editing a lane's value KEYS it at the playhead — always (R9 #18).
///
/// It used to write the static value while the parameter was unanimated,
/// which imitated AE's stopwatch: no stopwatch, no key. This app has no
/// stopwatch, and its ONE key affordance is the diamond — so the imitation
/// only meant that effects behaved unlike transforms, which key
/// unconditionally. One rule now: a value the user typed is a key.
///
/// The pixels do not move on the first edit: a track with a single key
/// resolves to that key at every frame, exactly as the static slot did.
///
/// [EffectParameter.value] STAYS — it carries the kind's spec default, and
/// it is the slot an AE-style stopwatch would switch off into if this app
/// ever grows one (the user's note when #18 was decided).
List<LayerEffect>? effectsWithLaneValueEdited(
  List<LayerEffect> effects, {
  required String laneId,
  required int frameIndex,
  required String input,
}) {
  if (frameIndex < 0) {
    return null;
  }
  return _editParameter(effects, laneId, (parameter, spec) {
    final value = parseEffectLaneValue(spec, input);
    if (value == null) {
      return null;
    }
    return parameter.copyWith(
      track: parameter.track.withKey(
        frameIndex,
        value,
        interpolation:
            parameter.track.keyAt(frameIndex)?.interpolation ??
            PropertyKeyInterpolation.linear,
      ),
    );
  });
}

/// AE's group Reset for ONE effect header (R5, user 2026-08-09) — the same
/// rule the transform group's takes: **키를 삭제하진 않고 값만 리셋**.
///
/// An effect parameter has BOTH a static slot and a track, so the two cases
/// separate cleanly: an unkeyed parameter resets its static value (no key is
/// authored — a reset must not turn a static property into an animated one),
/// and a keyed one takes the spec default at the scope frames with its
/// existing interpolation kept.
///
/// [keyedFramesOnly] tells the two scopes apart, exactly as it does for the
/// transform group: at the playhead a keyed lane MUST take a key (the only
/// way the value THERE can be the default), while a lane-range selection
/// means "reset the selected keys" and invents none.
///
/// Null when [laneId] is not an effect GROUP header, or nothing changed.
List<LayerEffect>? effectsWithGroupReset(
  List<LayerEffect> effects, {
  required String laneId,
  required Iterable<int> frameIndexes,
  bool keyedFramesOnly = false,
}) {
  final address = parseEffectLaneId(laneId);
  if (address == null || address.parameterId != null) {
    return null;
  }
  final frames = frameIndexes.where((frame) => frame >= 0).toSet();
  if (frames.isEmpty) {
    return null;
  }
  for (var index = 0; index < effects.length; index += 1) {
    final effect = effects[index];
    if (effect.id != address.effectId) {
      continue;
    }
    var next = effect;
    var changed = false;
    for (final spec in effectParametersOf(effect.kind)) {
      final parameter = effect.parameterOf(spec.id);
      if (parameter.track.isEmpty) {
        if (parameter.value == spec.defaultValue) {
          continue;
        }
        next = next.withParameter(
          spec.id,
          parameter.copyWith(value: spec.defaultValue),
        );
        changed = true;
        continue;
      }
      var track = parameter.track;
      for (final frame in frames) {
        if (keyedFramesOnly && parameter.track.keyAt(frame) == null) {
          continue;
        }
        track = track.withKey(
          frame,
          spec.defaultValue,
          interpolation:
              parameter.track.keyAt(frame)?.interpolation ??
              PropertyKeyInterpolation.linear,
        );
      }
      if (track == parameter.track) {
        continue;
      }
      next = next.withParameter(spec.id, parameter.copyWith(track: track));
      changed = true;
    }
    if (!changed) {
      return null;
    }
    final chain = List<LayerEffect>.of(effects);
    chain[index] = next;
    return chain;
  }
  return null;
}

/// Shifts EVERY key of ONE effect lane inside [rangeStartIndex,
/// [rangeEndIndexExclusive]) by [frameDelta] — the lane-scoped range move
/// (UI-R23 #3): rigid group, one delta, all-or-nothing. Null when nothing
/// moves, a landing dips below 0, or a landing collides with an UNSHIFTED
/// key on the same lane.
List<LayerEffect>? effectsWithLaneKeysShifted(
  List<LayerEffect> effects, {
  required String laneId,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  return _editParameter(effects, laneId, (parameter, spec) {
    // The shared shift loop — transform/name-tag families ride the same one.
    final next = parameter.track.withRangedKeysShifted(
      rangeStartIndex: rangeStartIndex,
      rangeEndIndexExclusive: rangeEndIndexExclusive,
      frameDelta: frameDelta,
    );
    return next == null ? null : parameter.copyWith(track: next);
  });
}

/// Shifts every ranged key of EVERY [laneIds] lane by [frameDelta] — the
/// MULTI-LANE range move (R26 #3): rigid group, one delta, all-or-nothing
/// ACROSS lanes. A lane with no key in the range rides along; a lane whose
/// landing is blocked vetoes the WHOLE move.
List<LayerEffect>? effectsWithLaneSpanKeysShifted(
  List<LayerEffect> effects, {
  required List<String> laneIds,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  var current = effects;
  var movedAny = false;
  for (final laneId in laneIds) {
    final keys = effectLaneKeyFrames(current, laneId);
    final hasRangedKey = keys.any(
      (frame) => frame >= rangeStartIndex && frame < rangeEndIndexExclusive,
    );
    if (!hasRangedKey) {
      continue;
    }
    final next = effectsWithLaneKeysShifted(
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
Set<int> effectLaneKeyFrames(List<LayerEffect> effects, String laneId) {
  final address = parseEffectLaneId(laneId);
  final parameterId = address?.parameterId;
  if (address == null) {
    return const {};
  }
  for (final effect in effects) {
    if (effect.id != address.effectId) {
      continue;
    }
    if (parameterId == null) {
      // The header row summarises its members.
      return {
        for (final parameter in effect.parameters.values)
          ...parameter.track.keys.keys,
      };
    }
    return effect.parameterOf(parameterId).track.keys.keys.toSet();
  }
  return const {};
}

/// [effects] with [effect] appended — "Add effect".
List<LayerEffect> effectsWithAdded(
  List<LayerEffect> effects,
  LayerEffect effect,
) => [...effects, effect];

/// [effects] without the one named by [effectId]; null when it is not there
/// (so the caller commits nothing).
List<LayerEffect>? effectsWithRemoved(
  List<LayerEffect> effects,
  EffectId effectId,
) {
  final next = [
    for (final effect in effects)
      if (effect.id != effectId) effect,
  ];
  return next.length == effects.length ? null : next;
}

/// [effects] with one entry's enable switch flipped (AE's per-effect fx
/// eyeball); null when the id is not present.
List<LayerEffect>? effectsWithEnabledToggled(
  List<LayerEffect> effects,
  EffectId effectId,
) {
  var found = false;
  final next = [
    for (final effect in effects)
      if (effect.id == effectId)
        (() {
          found = true;
          return effect.copyWith(enabled: !effect.enabled);
        })()
      else
        effect,
  ];
  return found ? next : null;
}

/// Rebuilds the ONE effect a parameter lane addresses through [edit]; null
/// when the lane is not an effect parameter lane, the effect is gone, the
/// parameter is not part of its kind, or [edit] declines the change.
List<LayerEffect>? _editParameter(
  List<LayerEffect> effects,
  String laneId,
  EffectParameter? Function(EffectParameter parameter, EffectParameterSpec spec)
  edit,
) {
  final address = parseEffectLaneId(laneId);
  final parameterId = address?.parameterId;
  if (address == null || parameterId == null) {
    return null;
  }
  for (var index = 0; index < effects.length; index += 1) {
    final effect = effects[index];
    if (effect.id != address.effectId) {
      continue;
    }
    final spec = effectParameterSpecOf(effect.kind, parameterId);
    if (spec == null) {
      return null;
    }
    final edited = edit(effect.parameterOf(parameterId), spec);
    if (edited == null) {
      return null;
    }
    final next = List<LayerEffect>.of(effects);
    next[index] = effect.withParameter(parameterId, edited);
    return next;
  }
  return null;
}
