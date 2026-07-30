import 'dart:ui' show Offset;

import '../../models/layer_effect.dart';
import '../../models/property_track.dart';
import 'property_lane_model.dart';

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

bool laneIsEffectLane(PropertyLaneRow lane) =>
    parseEffectLaneId(lane.laneId) != null;

/// The lane rows for [effects]: each effect's header, and its parameter
/// lanes while [isExpanded] says the header is twirled open (AE group
/// collapse, exactly like the Transform group).
///
/// [valueAt] resolves a parameter's value for the blue value column; the
/// caller owns it because the sample must come from the same resolver the
/// composite uses.
List<PropertyLaneRow> effectPropertyLanes(
  List<LayerEffect> effects, {
  required bool Function(EffectId effectId) isExpanded,
  double Function(EffectId effectId, String parameterId, int frameIndex)?
  valueAt,
}) {
  if (effects.isEmpty) {
    return const [];
  }
  final rows = <PropertyLaneRow>[];
  for (final effect in effects) {
    final expanded = isExpanded(effect.id);
    rows.add(
      PropertyLaneRow(
        laneId: effectGroupLaneId(effect.id),
        // A BYPASSED effect says so in its own row: the label is the only
        // place a disabled effect can show, and a silent one would read as
        // a broken parameter.
        label: effect.enabled
            ? effect.kind.label
            : '${effect.kind.label} (off)',
        // The header carries its members' key union (UI-R20 #13), so one
        // glance finds the effect's keys while it stays collapsed.
        keyedFrames: {
          for (final parameter in effect.parameters.values)
            ...parameter.track.keys.keys,
        },
        showsKeyNavigator: false,
        isGroupHeader: true,
        groupExpanded: expanded,
      ),
    );
    if (!expanded) {
      continue;
    }
    for (final spec in effectParametersOf(effect.kind)) {
      final parameter = effect.parameterOf(spec.id);
      rows.add(
        PropertyLaneRow(
          laneId: effectLaneId(effect.id, spec.id),
          label: spec.label,
          keyedFrames: parameter.track.keys.keys.toSet(),
          holdOutFrames: {
            for (final entry in parameter.track.keys.entries)
              if (entry.value.interpolation == PropertyKeyInterpolation.hold)
                entry.key,
          },
          valueLabel: valueAt == null
              ? null
              : (frameIndex) => formatEffectLaneValue(
                  spec,
                  valueAt(effect.id, spec.id, frameIndex),
                ),
          scrubValue: (label, delta) =>
              scrubEffectLaneValue(spec, label, delta),
        ),
      );
    }
  }
  return rows;
}

/// The display order of ONE effect's lanes — the lane-row span (R26 #3)
/// resolves anchor→head against this, so a multi-lane range move can grab a
/// whole effect but never reach across two effects.
List<String> effectLaneDisplayOrder(LayerEffect effect) => [
  for (final spec in effectParametersOf(effect.kind))
    effectLaneId(effect.id, spec.id),
];

/// The display-ordered lane span from [anchorLaneId] to [headLaneId] within
/// ONE effect (R26 #3's Excel span rule, effect-scoped); null when neither
/// endpoint is an effect lane, so the caller falls through to
/// [transformLaneSpan].
///
/// An effect's GROUP HEADER as either endpoint selects the WHOLE effect
/// ("모두에 적용되는 그 행"). Endpoints in DIFFERENT effects collapse to the
/// anchor alone: a rigid multi-lane move across two effects has no meaning
/// the model can honour all-or-nothing.
List<String>? effectLaneSpan(
  List<LayerEffect> effects,
  String anchorLaneId,
  String headLaneId,
) {
  final anchor = parseEffectLaneId(anchorLaneId);
  final head = parseEffectLaneId(headLaneId);
  if (anchor == null && head == null) {
    return null;
  }
  final effectId = anchor?.effectId ?? head!.effectId;
  LayerEffect? owner;
  for (final effect in effects) {
    if (effect.id == effectId) {
      owner = effect;
      break;
    }
  }
  if (owner == null) {
    return [anchorLaneId];
  }
  final order = effectLaneDisplayOrder(owner);
  // A header endpoint, a foreign endpoint, or an unknown parameter: the
  // whole effect when the header asked for it, the anchor alone otherwise.
  if (anchor == null || anchor.parameterId == null) {
    return order;
  }
  if (head == null || head.effectId != effectId) {
    return [anchorLaneId];
  }
  if (head.parameterId == null) {
    return order;
  }
  final anchorIndex = order.indexOf(anchorLaneId);
  final headIndex = order.indexOf(headLaneId);
  if (anchorIndex < 0 || headIndex < 0) {
    return [anchorLaneId];
  }
  final low = anchorIndex < headIndex ? anchorIndex : headIndex;
  final high = anchorIndex < headIndex ? headIndex : anchorIndex;
  return order.sublist(low, high + 1);
}

/// Whether a lane selection covering [spanLaneIds] should wash an effect's
/// GROUP HEADER row — the header's counterpart of the transform group's
/// all-members rule.
///
/// Approximate on purpose: the lane ids alone do not say how many
/// parameters the effect has (that needs its kind), so "more than one lane
/// and all of them this effect's" is the test. Selecting two of a
/// three-lane effect therefore also washes the header, which costs nothing
/// — it is an indicator, not a permission.
bool effectGroupHeaderCovered(String headerLaneId, List<String> spanLaneIds) {
  final header = parseEffectLaneId(headerLaneId);
  if (header == null || header.parameterId != null || spanLaneIds.length <= 1) {
    return false;
  }
  for (final laneId in spanLaneIds) {
    final address = parseEffectLaneId(laneId);
    if (address == null || address.effectId != header.effectId) {
      return false;
    }
  }
  return true;
}

/// AE-style value formatting for an effect parameter.
String formatEffectLaneValue(EffectParameterSpec spec, double value) {
  return switch (spec.unit) {
    EffectParameterUnit.number => _number(value),
    EffectParameterUnit.degrees => '${_number(value)}°',
    EffectParameterUnit.pixels => '${_number(value)} px',
  };
}

/// Parses what the value editor accepts for [spec]: the bare number, with
/// or without its unit suffix, clamped to the parameter's range. Null on a
/// parse failure (the editor then ignores the input, like the transform
/// lanes).
double? parseEffectLaneValue(EffectParameterSpec spec, String input) {
  final raw = input
      .replaceAll('°', '')
      .replaceAll('px', '')
      .replaceAll('%', '')
      .trim();
  final value = double.tryParse(raw);
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
  return formatEffectLaneValue(spec, spec.clamp(current + dragDelta.dx * 0.5));
}

String _number(double value) {
  final rounded = double.parse(value.toStringAsFixed(1));
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
}
