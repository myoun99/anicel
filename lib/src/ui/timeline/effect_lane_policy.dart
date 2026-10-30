import 'dart:ui' show Offset;

import '../../models/key_mark.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/transform_track.dart' show TransformPose;
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart';
import '../text/readout_text.dart';
import '../theme/lane_curve_palette.dart';
import 'property_lane_model.dart';
import 'scale_lane_form.dart';
import 'se_name_tag_lane_editing.dart' show parseBoolInput;
import 'transform_lane_policy.dart'
    show transformPositionLane, transformPropertyLanes;

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

/// The effect of [effects] the CANVAS's box drives while [laneId] is stood
/// on, and the [lane] of it whose keys the box moves — R5 #10, 「an fx
/// declares its own manipulators」 (`canvasManipulatorsForLane`): an
/// effect on and drawing declares, on its header and on the lanes its
/// keys keep as a transform's ([LayerEffect.transformLaneAt]), the box
/// over the picture it draws — where it stands — as a transform's header
/// and its Position and Scale declare the row's; or a point's cross — on
/// its header, its first point's. Its colours and numbers, and every lane
/// of any other effect, declare none. Null for every other lane.
///
/// 🗣️F-477 (유저 2026-10-26): 「fx헤더에 서있으면 트랜스폼처럼 조작할수있는거
/// 캔버스에 뜨고 조작가능하고, 키에 서도 해당 키 조작가능한거면 가능할수
/// 있게」. ↩️Only the transform's lanes declared one, so a cel number's
/// header and its Position and Scale drew nothing on the canvas.
({LayerEffect effect, String lane})? effectBoxedOn(
  List<LayerEffect> effects,
  String? laneId,
) {
  final address = laneId == null ? null : parseEffectLaneId(laneId);
  if (address == null) {
    return null;
  }
  for (final effect in effects) {
    if (effect.id != address.effectId) {
      continue;
    }
    final lane =
        address.parameterId ??
        (effect.kind.drawsItsOwnPicture
            ? effectStandLanes.first
            : effect.points.keys.firstOrNull);
    return effect.enabled &&
            lane != null &&
            effect.transformLaneAt(lane) != null
        ? (effect: effect, lane: lane)
        : null;
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
/// resolver the composite uses. [standAt] is where the keys a lane of an
/// effect keeps as a transform's ([LayerEffect.transformLaneAt]) stand at
/// a time — where it stands its picture, a point ([effectStandPose]) —
/// the caller knows the paper. Null for either leaves its lanes unvalued:
/// a rail with no cut to read them in.
///
/// [cutRows] are the rows a row parameter ([EffectParameterUnit.layer])
/// may name: the cut's — 🗣️I-132-Q16 a 「같은 컷의 행」 — none for a
/// track's chain, which is no cut's.
List<PropertyLaneRow> effectPropertyLanes(
  List<LayerEffect> effects, {
  List<Layer> cutRows = const [],
  required bool Function(EffectId effectId) isExpanded,
  double Function(EffectId effectId, String parameterId, double time)?
  valueAt,
  TransformPose Function(EffectId effectId, String lane, double time)?
  standAt,
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
        label: effect.labelFor(AppText.language),
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
      rows.addAll(_standLanes(effect, standAt));
    }
    for (final (index, spec) in effect.specs.indexed) {
      // A point is a Position of its own: the transform's row of it.
      if (effect.points[spec.id] case final point?) {
        final lane = spec.id;
        rows.add(
          transformPositionLane(
            point,
            laneId: effectLaneId(effect.id, lane),
            label: spec.labelFor(AppText.language),
            poseAt: standAt == null
                ? null
                : (time) => standAt(effect.id, lane, time),
          ),
        );
        continue;
      }
      if (effect.layers.containsKey(spec.id)) {
        rows.add(_rowLane(effect, spec, cutRows));
        continue;
      }
      // A colour's keys are its own ([LayerEffect.colors]); a number's its
      // parameter's.
      final keys = effect.laneTrack(spec.id)!;
      final valueKind = switch (spec.unit) {
        EffectParameterUnit.choice => PropertyLaneValueKind.choice,
        // As an SE name tag's inks are: the shared colour swatch.
        EffectParameterUnit.color => PropertyLaneValueKind.color,
        // As a name tag's Bold is: a ring a tap flips.
        EffectParameterUnit.flag => PropertyLaneValueKind.boolean,
        _ => PropertyLaneValueKind.number,
      };
      // A menu has nothing between its words to scrub through, nor a line
      // to lay on a header graph — a flag's lane, with words for a ring.
      // Nor has a colour: its line would be a number no one reads. Nor, of
      // course, a flag.
      final numbered = valueKind == PropertyLaneValueKind.number;
      rows.add(
        PropertyLaneRow(
          laneId: effectLaneId(effect.id, spec.id),
          label: spec.labelFor(AppText.language),
          keyMarks: keyMarksOf(keys),
          keyNames: keys.namedKeysByFrame,
          valueKind: valueKind,
          choices: [
            for (final choice in spec.choices)
              choice.labelFor(AppText.language),
          ],
          valueLabel: valueAt == null
              ? null
              : (frameIndex) => formatEffectLaneValue(
                  spec,
                  valueAt(effect.id, spec.id, frameIndex.toDouble()),
                ),
          scrubValue: !numbered
              ? null
              : (label, delta) => scrubEffectLaneValue(spec, label, delta),
          curve: valueAt == null || !numbered
              ? null
              : (
                  parts: [LaneCurvePalette.effectParameter(index)],
                  at: (time) => [valueAt(effect.id, spec.id, time)],
                  sides: keys.sidesByFrame,
                  way: null,
                ),
        ),
      );
    }
  }
  return rows;
}

/// The lane of row parameter [spec] of [effect] ([EffectParameterUnit
/// .layer]): a menu, as a choice's, of none and [cutRows] by name, whose
/// pick writes the row's id ([effectLaneRowText]) — one row at every
/// frame, and no keys to walk to, as the SE audio lane has none
/// (🗣️I-132-Q16 a: 「없음 + 행 이름들, 키 없음」).
PropertyLaneRow _rowLane(
  LayerEffect effect,
  EffectParameterSpec spec,
  List<Layer> cutRows,
) {
  final named = effectLaneRowNamed(effect.layers[spec.id], cutRows);
  final none = AppText.strings.commonNone;
  return PropertyLaneRow(
    laneId: effectLaneId(effect.id, spec.id),
    label: spec.labelFor(AppText.language),
    keyMarks: const {},
    showsKeyNavigator: false,
    valueKind: PropertyLaneValueKind.choice,
    choices: [none, for (final row in cutRows) row.name],
    choiceValues: [
      effectLaneRowText(null),
      for (final row in cutRows) effectLaneRowText(row.id),
    ],
    choiceHeld: effectLaneRowText(named?.id),
    valueLabel: (_) => named?.name ?? none,
  );
}

/// The row of [rows] that [row] names — null for none, and for a row that
/// is not among them: deleted, or named in another cut, it reads as none,
/// as a dangling attach does (`attachedBaseOf`).
Layer? effectLaneRowNamed(LayerId? row, List<Layer> rows) =>
    row == null ? null : rows.where((layer) => layer.id == row).firstOrNull;

/// What a row parameter's lane writes for [row]: its id's value, or the
/// empty text for none — read back by [effectLaneRowOf].
String effectLaneRowText(LayerId? row) => row?.value ?? '';

/// The row [input] names, as a row parameter's lane writes it
/// ([effectLaneRowText]) — null for none.
LayerId? effectLaneRowOf(String input) =>
    input.isEmpty ? null : LayerId(input);

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
  TransformPose Function(EffectId effectId, String lane, double time)?
  standAt,
) {
  final ids = {
    for (final lane in effectStandLanes) effectLaneId(effect.id, lane),
  };
  return [
    for (final row in transformPropertyLanes(
      effect.stand,
      scaleForm: effectStandScaleForm,
      // Any lane of the stand names its keys.
      poseAt: standAt == null
          ? null
          : (time) => standAt(effect.id, effectStandLanes.first, time),
      laneIdOf: (lane) => effectLaneId(effect.id, lane),
    ))
      if (ids.contains(row.laneId)) row,
  ];
}

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
    EffectParameterUnit.degrees => turnsReadoutText(value),
    EffectParameterUnit.pixels => '${columnValueText(value)} px',
    EffectParameterUnit.choice =>
      spec.choices[spec.clamp(value).round()].labelFor(AppText.language),
    EffectParameterUnit.color => formatLaneColorValue(value.toInt()),
    EffectParameterUnit.flag => flagLaneWord(effectFlagIsOn(value)),
    // A point prints as the transform's Position does, on its own row
    // ([transformPositionLane]) — it is no number to print here; a row by
    // its name ([_rowLane]).
    EffectParameterUnit.point || EffectParameterUnit.layer => '',
  };
}

/// Parses what the value editor accepts for [spec]: the bare number, with
/// or without its unit suffix, clamped to the parameter's range — or, on a
/// menu, one of its words, in the program's language or the model's
/// English — on a flag, `on` or `off` as its ring writes them. Null on a
/// parse failure (the editor then ignores the input,
/// like the transform lanes).
double? parseEffectLaneValue(EffectParameterSpec spec, String input) {
  if (spec.unit == EffectParameterUnit.choice) {
    final word = input.trim();
    final index = spec.choices.indexWhere(
      (choice) =>
          choice.labelFor(AppText.language) == word || choice.label == word,
    );
    return index < 0 ? null : index.toDouble();
  }
  if (spec.unit == EffectParameterUnit.flag) {
    return switch (parseBoolInput(input)) {
      final on? => on ? 1 : 0,
      null => null,
    };
  }
  final value = columnValueOf(input);
  if (value == null) {
    return null;
  }
  return spec.clamp(value);
}

/// AE-style value scrubbing: the horizontal drag drives the number — an
/// angle's two boxes their own ([scrubbedAngle]) — in the same text form
/// the value editor parses (the release commits through the ordinary
/// onSetValue path, so one drag is one undo).
String? scrubEffectLaneValue(
  EffectParameterSpec spec,
  String currentLabel,
  Offset dragDelta,
) {
  final current = parseEffectLaneValue(spec, currentLabel);
  if (current == null) {
    return null;
  }
  final scrubbed = spec.unit == EffectParameterUnit.degrees
      ? scrubbedAngle(current, dragDelta)
      : scrubbedNumber(current, dragDelta);
  return formatEffectLaneValue(spec, spec.clamp(scrubbed));
}
