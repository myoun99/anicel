// Per-lane key edits on a layer's EFFECT CHAIN, keyed by the lane ids
// [effectPropertyLanes] emits. Every function returns the edited chain (or
// null when the edit is a no-op / not an effect lane) — callers commit it as
// ONE undo step, exactly like the transform-lane helpers next door.
//
// The chain is a LIST, so each edit finds its effect by id, rebuilds that one
// entry and leaves the rest identical.
//
// 🚨WHERE AN EFFECT STANDS ITS PICTURE IS A TRANSFORM'S LANES (I-65): a cel
// number's Position and Scale ([LayerEffect.stand]) are edited by the
// transform's own verbs on that track — the reference fx's way (F-374) —
// so they key, take values, reset and name as a layer's do.

import '../../models/canvas_size.dart';
import '../../models/layer_effect.dart';
import '../../models/property_track.dart';
import '../../models/transform_track.dart';
import 'effect_lane_policy.dart';
import 'property_lane_lens.dart';
import 'transform_lane_editing.dart'
    show
        transformLaneLens,
        transformTrackWithGroupReset,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneValueEdited;

/// Adds a key at [frameIndex] holding the lane's RESOLVED value there (AE
/// behaviour: keying a property freezes its current value), or removes the
/// existing one — the keyframe navigator's diamond toggle.
///
/// Where an effect stands is resolved on [paper], the paper its row stands
/// on — its rest is that paper's middle ([effectStandPose]); without one
/// such a lane keys nothing.
List<LayerEffect>? effectsWithLaneKeyToggled(
  List<LayerEffect> effects, {
  required String laneId,
  required int frameIndex,
  CanvasSize? paper,
}) {
  if (frameIndex < 0) {
    return null;
  }
  if (_standsOn(effects, laneId)) {
    return paper == null
        ? null
        : _editStand(
            effects,
            laneId,
            (stand, lane) => transformTrackWithLaneKeyToggled(
              stand,
              laneId: lane,
              frameIndex: frameIndex,
              resolvedPose: effectStandPose(
                effectStandAt(stand, frameIndex.toDouble()),
                paper,
              ),
            ),
          );
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
// drag. Re-timing is the span's move now — select the span, move the span
// ([laneSpanKeysShifted] on [effectLaneLens], every home's one move since
// F-374) — and a dead single-key mover left lying here is an invitation to
// wire the second grammar back.

/// The key window's write on effect lane [laneId] (F-17 · I-89): the keys
/// inside [frames] named as [naming] says (a null name un-names them) — all
/// collapsed onto ONE value, [adopted] where the name already holds one
/// elsewhere in the naming space — and then given [pick]: its sides alone
/// where the keys walk no path ([KeyTypePick.sidesAlone]) — a parameter's
/// — and all of it where they do, as a transform's Position's
/// ([effectLaneWalksAPath]). ONE write of the lane
/// ([PropertyTrack.withKeysWritten]), as a transform lane's. Null when
/// nothing changed.
///
/// The range form of naming — see [PropertyTrack.withRangeNamed] for why
/// the collapse is the intent rather than a side effect.
List<LayerEffect>? effectsWithLaneKeysWritten(
  List<LayerEffect> effects, {
  required String laneId,
  required Set<int> frames,
  ({String? name, int? preferredFrame})? naming,
  PropertyKey<Object?>? adopted,
  KeyTypePick pick = const KeyTypePick(),
}) {
  final walks = effectLaneWalksAPath(laneId);
  return effectLaneLens(laneId)?.update(
    effects,
    <U>(PropertyTrack<U> lane) => lane.withKeysWritten(
      frames: frames,
      naming: naming == null
          ? null
          : (
              name: naming.name,
              adopted: adopted as PropertyKey<U>?,
              preferredFrame: naming.preferredFrame,
            ),
      pick: walks ? pick : pick.sidesAlone,
    ),
  );
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
///
/// Where an effect stands is typed as a transform's Position and Scale are
/// ([transformTrackWithLaneValueEdited]) — the Scale by the transform
/// tool's 「배율 연동」, [scaleLinked], as a layer's.
List<LayerEffect>? effectsWithLaneValueEdited(
  List<LayerEffect> effects, {
  required String laneId,
  required int frameIndex,
  required String input,
  required bool scaleLinked,
}) {
  if (frameIndex < 0) {
    return null;
  }
  if (_standsOn(effects, laneId)) {
    return _editStand(
      effects,
      laneId,
      (stand, lane) => transformTrackWithLaneValueEdited(
        stand,
        laneId: lane,
        frameIndex: frameIndex,
        input: input,
        scaleForm: effectStandScaleForm,
        scaleLinked: scaleLinked,
      ),
    );
  }
  return _editParameter(effects, laneId, (parameter, spec) {
    final value = parseEffectLaneValue(spec, input);
    if (value == null) {
      return null;
    }
    return parameter.copyWith(
      track: parameter.track.withKey(frameIndex, value),
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
/// existing interpolation kept. Where the effect stands is reset as a
/// transform group is ([transformTrackWithGroupReset]): to where a row
/// stands at rest on [paper] — left as it is without one.
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
  CanvasSize? paper,
}) {
  final address = parseEffectLaneId(laneId);
  if (address == null || address.parameterId != null) {
    return null;
  }
  final frames = frameIndexes.where((frame) => frame >= 0).toSet();
  if (frames.isEmpty) {
    return null;
  }
  return _editEffect(effects, address.effectId, (effect) {
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
        track = track.withKey(frame, spec.defaultValue);
      }
      if (track == parameter.track) {
        continue;
      }
      next = next.withParameter(spec.id, parameter.copyWith(track: track));
      changed = true;
    }
    final rest = paper == null ? null : layerIdentityPose(paper);
    final stand = rest == null
        ? null
        : transformTrackWithGroupReset(
            effect.stand,
            frameIndexes: frames,
            identity: rest,
            // No anchor lane: nothing is reset to it.
            defaultAnchorPoint: rest.center,
            keyedFramesOnly: keyedFramesOnly,
          );
    if (stand != null) {
      next = next.copyWith(stand: stand);
      changed = true;
    }
    return changed ? next : null;
  });
}

/// The effect family's lane table. A lane is addressed by its parsed
/// (effectId, lane) over the chain — a different key law from the
/// fixed-field tracks, so the lens walks the list rather than reading a
/// field: a parameter's through [_editParameter], and where the effect
/// stands through the transform's own table ([transformLaneLens]) on
/// [LayerEffect.stand]. The group header is a lane too (its keyed frames
/// are its members' union) but holds no track of its own, so an edit
/// through it answers null. Null for an id that is not an effect lane at
/// all.
///
/// The shared shift loop — transform/name-tag families ride the same one:
/// `LaneKeysShift.keysShifted` over this table.
LaneLens<List<LayerEffect>>? effectLaneLens(String laneId) =>
    parseEffectLaneId(laneId) == null ? null : _EffectLaneLens(laneId);

class _EffectLaneLens implements LaneLens<List<LayerEffect>> {
  const _EffectLaneLens(this.laneId);

  final String laneId;

  @override
  List<LayerEffect>? update(List<LayerEffect> effects, PropertyLaneEdit edit) =>
      _standsOn(effects, laneId)
      ? _editStand(
          effects,
          laneId,
          (stand, lane) => transformLaneLens(lane)?.update(stand, edit),
        )
      : _editParameter(effects, laneId, (parameter, spec) {
          final next = edit(parameter.track);
          return next == null ? null : parameter.copyWith(track: next);
        });

  @override
  Set<int> keyFrames(List<LayerEffect> effects) =>
      effectLaneKeyFrames(effects, laneId);

  /// A lane's keys — none on a header, which keeps none of its own (its
  /// keys are its members').
  @override
  Map<int, PropertyKey<Object?>> keysOf(List<LayerEffect> effects) =>
      _readLane(
        effects,
        laneId,
        (effect, lane) => effect.laneTrack(lane)?.keys,
      ) ??
      const {};

  /// A parameter shows the number it holds ([formatEffectLaneValue]); a
  /// header holds none, and where the effect stands is points, as a
  /// transform's Position and Scale are.
  @override
  double? numberShown(double held) => switch (parseEffectLaneId(laneId)) {
    (effectId: _, parameterId: final lane?)
        when !effectStandLanes.contains(lane) =>
      held,
    _ => null,
  };

  /// A number given a parameter is held clamped to its range, as its value
  /// editor takes it typed ([parseEffectLaneValue]).
  @override
  double? numberHeld(List<LayerEffect> effects, double shown) => _readLane(
    effects,
    laneId,
    (effect, lane) => effectParameterSpecOf(effect.kind, lane)?.clamp(shown),
  );
}

/// What [read] answers of the effect a lane addresses, given the lane — a
/// parameter's id or one where the effect stands — null when the lane is a
/// header or its effect is not in the chain: the read twin of
/// [_editEffect].
R? _readLane<R>(
  List<LayerEffect> effects,
  String laneId,
  R? Function(LayerEffect effect, String lane) read,
) {
  final address = parseEffectLaneId(laneId);
  final lane = address?.parameterId;
  if (address == null || lane == null) {
    return null;
  }
  for (final effect in effects) {
    if (effect.id == address.effectId) {
      return read(effect, lane);
    }
  }
  return null;
}

/// Whether [laneId] is one where its effect in [effects] stands its picture
/// ([LayerEffect.standLaneOf]).
bool _standsOn(List<LayerEffect> effects, String laneId) =>
    _readLane(effects, laneId, (effect, lane) => effect.standLaneOf(lane)) !=
    null;

/// Rebuilds where the effect a stand lane addresses stands through [edit],
/// handed the transform lane the lane is ([LayerEffect.standLaneOf]); null
/// when the lane is not one, the effect is gone, or [edit] declines the
/// change — the stand's twin of [_editParameter].
List<LayerEffect>? _editStand(
  List<LayerEffect> effects,
  String laneId,
  TransformTrack? Function(TransformTrack stand, String lane) edit,
) {
  final address = parseEffectLaneId(laneId);
  final lane = address?.parameterId;
  if (address == null || lane == null) {
    return null;
  }
  return _editEffect(effects, address.effectId, (effect) {
    if (effect.standLaneOf(lane) == null) {
      return null;
    }
    final next = edit(effect.stand, lane);
    return next == null ? null : effect.copyWith(stand: next);
  });
}

/// Whether the key at [frameIndex] of effect lane [laneId] may give its
/// time up (I-89 ④): where the effect stands its picture, as a
/// transform's may ([transformLaneKeyCanRove]); a parameter's keys walk no
/// path, so none of theirs.
bool effectLaneKeyCanRove(
  List<LayerEffect> effects,
  String laneId,
  int frameIndex,
) =>
    _readLane(
      effects,
      laneId,
      (effect, lane) => switch (effect.standLaneOf(lane)) {
        final property? => transformLaneKeyCanRove(
          effect.stand,
          property,
          frameIndex,
        ),
        null => false,
      },
    ) ??
    false;

/// The lane's keyed frames — the keyframe navigator's ◀/▶ jump targets. A
/// header's are its members' — every lane of its effect ([LayerEffect
/// .lanes]).
Set<int> effectLaneKeyFrames(List<LayerEffect> effects, String laneId) {
  final address = parseEffectLaneId(laneId);
  if (address == null) {
    return const {};
  }
  for (final effect in effects) {
    if (effect.id != address.effectId) {
      continue;
    }
    final lanes = switch (address.parameterId) {
      final lane? => [lane],
      null => effect.lanes,
    };
    return {
      for (final lane in lanes) ...?effect.laneTrack(lane)?.keys.keys,
    };
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
) => _editEffect(
  effects,
  effectId,
  (effect) => effect.copyWith(enabled: !effect.enabled),
);

/// Rebuilds the ONE effect [effectId] names through [edit], returning the
/// chain with that slot replaced — null when the effect is not in the
/// chain, or [edit] declines the change by answering null.
///
/// The chain is a LIST, so every edit in this file is this walk: find by
/// id, rebuild the one entry, copy the list with that slot replaced. What
/// to DO with the found effect is the closure, which is why the group
/// reset, the parameter edits and the enable toggle can share it without
/// anything choosing between them.
List<LayerEffect>? _editEffect(
  List<LayerEffect> effects,
  EffectId effectId,
  LayerEffect? Function(LayerEffect effect) edit,
) {
  for (var index = 0; index < effects.length; index += 1) {
    final effect = effects[index];
    if (effect.id != effectId) {
      continue;
    }
    final edited = edit(effect);
    if (edited == null) {
      return null;
    }
    final next = List<LayerEffect>.of(effects);
    next[index] = edited;
    return next;
  }
  return null;
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
  return _editEffect(effects, address.effectId, (effect) {
    final spec = effectParameterSpecOf(effect.kind, parameterId);
    if (spec == null) {
      return null;
    }
    final edited = edit(effect.parameterOf(parameterId), spec);
    return edited == null
        ? null
        : effect.withParameter(parameterId, edited);
  });
}
