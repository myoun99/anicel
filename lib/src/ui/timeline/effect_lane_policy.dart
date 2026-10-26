import 'dart:ui' show Offset;

import '../../models/key_mark.dart';
import '../../models/layer_effect.dart';
import '../../models/transform_track.dart' show TransformPose, laneWalksAPath;
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart';
import '../text/readout_text.dart';
import '../theme/lane_curve_palette.dart';
import 'property_lane_model.dart';
import 'scale_lane_form.dart';
import 'transform_lane_policy.dart' show transformPropertyLanes;

// EFFECT LANES (R6) on the same lane substrate the Transform group uses.
//
// [PropertyLaneRow] was built generic for exactly this ("transform lanes
// today, layer-FX property lanes on the same base soon"), so an effect
// contributes one GROUP HEADER row per effect instance plus one member lane
// per parameter — and the grid, the key diamonds, the value editor, the
// scrubbing and the range move all work with no changes.
//
// Lane ids carry the effect's identity, because a layer holds a LIST of
// effects and two Blurs must not share a lane:
//   `fx-group:<effectId>`      the effect's header row
//   `fx:<effectId>:<paramId>`  one parameter lane
// The transform lanes keep their bare ids ('position', …), so the two
// address spaces cannot collide.

const String _groupPrefix = 'fx-group:';
const String _parameterPrefix = 'fx:';

String effectGroupLaneId(EffectId effectId) => '$_groupPrefix${effectId.value}';

String effectLaneId(EffectId effectId, String parameterId) =>
    '$_parameterPrefix${effectId.value}:$parameterId';

/// The effect (and parameter, for a member lane) a lane id addresses; null
/// when [laneId] is not an effect lane at all — which is how every existing
/// transform-lane path keeps working untouched.
({EffectId effectId, String? parameterId})? parseEffectLaneId(String laneId) {
  if (laneId.startsWith(_groupPrefix)) {
    final value = laneId.substring(_groupPrefix.length);
    if (value.isEmpty) {
      return null;
    }
    return (effectId: EffectId(value), parameterId: null);
  }
  if (!laneId.startsWith(_parameterPrefix)) {
    return null;
  }
  final rest = laneId.substring(_parameterPrefix.length);
  final separator = rest.lastIndexOf(':');
  if (separator <= 0 || separator == rest.length - 1) {
    return null;
  }
  return (
    effectId: EffectId(rest.substring(0, separator)),
    parameterId: rest.substring(separator + 1),
  );
}

/// Whether the keys of effect lane [laneId] walk a path: where an effect
/// stands its picture, as a transform's Position does ([laneWalksAPath]);
/// a parameter's never do. Asked of the id alone, as a copy's lanes and a
/// range's are — no parameter is named as such a lane is
/// ([effectStandLanes]).
bool effectLaneWalksAPath(String laneId) =>
    switch (parseEffectLaneId(laneId)) {
      (effectId: _, parameterId: final lane?)
          when effectStandLanes.contains(lane) =>
        laneWalksAPath(lane),
      _ => false,
    };

/// The effect of [effects] whose picture the CANVAS's box drives while
/// [laneId] is stood on — R5 #10, 「an fx declares its own manipulators」
/// (`canvasManipulatorsForLane`): an effect that draws its own picture, on
/// and drawing, declares the box over it on its header and on the lanes of
/// where it stands ([effectStandLanes]), as a transform's header and its
/// Position and Scale declare the row's. Its colour, and every lane of any
/// other effect, declare none. Null for every other lane.
///
/// 🗣️F-477 (유저 2026-10-26): 「fx헤더에 서있으면 트랜스폼처럼 조작할수있는거
/// 캔버스에 뜨고 조작가능하고, 키에 서도 해당 키 조작가능한거면 가능할수
/// 있게」. ↩️Only the transform's lanes declared one, so a cel number's
/// header and its Position and Scale drew nothing on the canvas.
LayerEffect? effectBoxedOn(List<LayerEffect> effects, String? laneId) {
  final address = laneId == null ? null : parseEffectLaneId(laneId);
  if (address == null) {
    return null;
  }
  final lane = address.parameterId;
  for (final effect in effects) {
    if (effect.id == address.effectId) {
      return effect.kind.drawsItsOwnPicture &&
              effect.enabled &&
              (lane == null || effect.standLaneOf(lane) != null)
          ? effect
          : null;
    }
  }
  return null;
}

/// The lane rows for [effects]: each effect's header, and its lanes while
/// [isExpanded] says the header is twirled open (AE group collapse, exactly
/// like the Transform group) — where it stands first, on a kind that draws
/// its own picture ([LayerEffect.lanes]), then its parameters.
///
/// [valueAt] resolves a parameter's value at a time — the blue value
/// column's at its frame, a header graph's curve between frames too (I-89
/// ③); the caller owns it because the sample must come from the same
/// resolver the composite uses. [standAt] is where an effect stands its
/// picture at a time ([effectStandPose]) — the caller knows the paper.
/// Null for either leaves its lanes unvalued: a rail with no cut to read
/// them in.
List<PropertyLaneRow> effectPropertyLanes(
  List<LayerEffect> effects, {
  required bool Function(EffectId effectId) isExpanded,
  double Function(EffectId effectId, String parameterId, double time)?
  valueAt,
  TransformPose Function(EffectId effectId, double time)? standAt,
}) {
  if (effects.isEmpty) {
    return const [];
  }
  final rows = <PropertyLaneRow>[];
  for (final effect in effects) {
    final expanded = isExpanded(effect.id);
    final lanes = [for (final lane in effect.lanes) effect.laneTrack(lane)!];
    rows.add(
      PropertyLaneRow(
        laneId: effectGroupLaneId(effect.id),
        // F-37 (유저 2026-09-15, F-37-Q1: 「전부 번역 — 레인 이름도
        // 한국어로」): the effect's name in the program language — the same
        // words its Add entry reads.
        label: effect.kind.labelFor(AppText.language),
        // AE's per-effect eyeball: the header carries this effect's own
        // on/off switch as the shared `fx` glyph. A bypassed effect keeps
        // its keys and says so HERE, rather than looking like a broken
        // parameter.
        groupEnabled: effect.enabled,
        // The header carries its members' key union (UI-R20 #13), so one
        // glance finds the effect's keys while it stays collapsed — with
        // the marks they wear and the names they carry, the same unions the
        // Transform header draws ([unionKeyMarks], [unionKeyNames]).
        keyMarks: unionKeyMarks([for (final lane in lanes) keyMarksOf(lane)]),
        keyNames: unionKeyNames(lanes),
        showsKeyNavigator: false,
        isGroupHeader: true,
        groupExpanded: expanded,
        headsAGraph: true,
      ),
    );
    if (!expanded) {
      continue;
    }
    if (effect.kind.drawsItsOwnPicture) {
      rows
        ..addAll(_standLanes(effect, standAt))
        ..add(_inkLane(effect, valued: valueAt != null));
    }
    for (final (index, spec) in effectParametersOf(effect.kind).indexed) {
      final parameter = effect.parameterOf(spec.id);
      rows.add(
        PropertyLaneRow(
          laneId: effectLaneId(effect.id, spec.id),
          label: spec.labelFor(AppText.language),
          keyMarks: keyMarksOf(parameter.track),
          keyNames: parameter.track.namedKeysByFrame,
          valueLabel: valueAt == null
              ? null
              : (frameIndex) => formatEffectLaneValue(
                  spec,
                  valueAt(effect.id, spec.id, frameIndex.toDouble()),
                ),
          scrubValue: (label, delta) =>
              scrubEffectLaneValue(spec, label, delta),
          curve: valueAt == null
              ? null
              : (
                  parts: [LaneCurvePalette.effectParameter(index)],
                  at: (time) => [valueAt(effect.id, spec.id, time)],
                  sides: parameter.track.sidesByFrame,
                  way: null,
                ),
        ),
      );
    }
  }
  return rows;
}

/// How the Scale lane where an effect stands its picture reads and is
/// typed: a layer's two, as the transform's (「트랜스폼에 있는거처럼」).
const ScaleLaneForm effectStandScaleForm = TwoScales();

/// [effect]'s lanes of where it stands: the transform's own Position and
/// Scale rows of [LayerEffect.stand] ([transformPropertyLanes]), under the
/// effect's ids, valued where [standAt] stands it.
///
/// 🗣️I-65-Q2 메모 (유저 2026-10-24): 「트랜스폼에 있는거처럼 위치/비율 두개
/// 키. 공용화된거 사용하면서」.
List<PropertyLaneRow> _standLanes(
  LayerEffect effect,
  TransformPose Function(EffectId effectId, double time)? standAt,
) {
  final ids = {
    for (final lane in effectStandLanes) effectLaneId(effect.id, lane),
  };
  return [
    for (final row in transformPropertyLanes(
      effect.stand,
      scaleForm: effectStandScaleForm,
      poseAt: standAt == null ? null : (time) => standAt(effect.id, time),
      laneIdOf: (lane) => effectLaneId(effect.id, lane),
    ))
      if (ids.contains(row.laneId)) row,
  ];
}

/// [effect]'s lane of the colour it draws its picture in ([LayerEffect
/// .ink]): a colour lane, as an SE name tag's inks are — the value cell the
/// shared colour swatch, no line on a header graph. Unvalued where [valued]
/// is not, as the parameters' lanes are.
PropertyLaneRow _inkLane(LayerEffect effect, {required bool valued}) =>
    PropertyLaneRow(
      laneId: effectLaneId(effect.id, effectInkLane),
      label: AppText.strings.effectParameterName(effectInkLane, 'Ink'),
      keyMarks: keyMarksOf(effect.ink),
      keyNames: effect.ink.namedKeysByFrame,
      valueKind: PropertyLaneValueKind.color,
      valueLabel: valued
          ? (frameIndex) => formatLaneColorValue(
              effectInkAt(effect.ink, frameIndex.toDouble()),
            )
          : null,
    );

/// The display order of ONE effect's member lanes — the order the rail
/// draws them under the effect's group header ([LayerEffect.lanes]).
///
/// 🪦`effectLaneSelectionOrder` (header first, then these) and
/// `effectLaneSpan` (a span sliced out of it, effect-scoped) are gone: the
/// span is sliced out of the rows the rail ACTUALLY DREW
/// (`laneSpanOverDrawnRows`), which carry the header as a row like any
/// other. R9 #20 stands, restated: the header used to sit outside the
/// order and be handled by a branch, so a drag from the header to the
/// SECOND parameter selected every parameter — selection did something
/// other than what the drag drew.
List<String> effectLaneDisplayOrder(LayerEffect effect) => [
  for (final lane in effect.lanes) effectLaneId(effect.id, lane),
];

/// AE-style value formatting for an effect parameter.
String formatEffectLaneValue(EffectParameterSpec spec, double value) {
  return switch (spec.unit) {
    EffectParameterUnit.number => columnValueText(value),
    EffectParameterUnit.degrees => '${columnValueText(value)}°',
    EffectParameterUnit.pixels => '${columnValueText(value)} px',
  };
}

/// Parses what the value editor accepts for [spec]: the bare number, with
/// or without its unit suffix, clamped to the parameter's range. Null on a
/// parse failure (the editor then ignores the input, like the transform
/// lanes).
double? parseEffectLaneValue(EffectParameterSpec spec, String input) {
  final value = columnValueOf(input);
  if (value == null) {
    return null;
  }
  return spec.clamp(value);
}

/// AE-style value scrubbing: the horizontal drag drives the number, in the
/// same text form the value editor parses (the release commits through the
/// ordinary onSetValue path, so one drag is one undo).
String? scrubEffectLaneValue(
  EffectParameterSpec spec,
  String currentLabel,
  Offset dragDelta,
) {
  final current = parseEffectLaneValue(spec, currentLabel);
  if (current == null) {
    return null;
  }
  return formatEffectLaneValue(
    spec,
    spec.clamp(scrubbedNumber(current, dragDelta)),
  );
}
