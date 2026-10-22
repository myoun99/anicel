import 'package:flutter/foundation.dart' show ValueListenable;

import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import 'effect_lane_policy.dart' show effectGroupLaneId, parseEffectLaneId;
import 'reference_lane_policy.dart'
    show referenceGroupLaneId, referenceLaneDisplayOrder;
import 'se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId, seNameTagLaneDisplayOrder;
import 'transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;

/// The rail's half of R10 #19: WHICH row the frame-axis verbs act on, and
/// how to move it by pressing a label.
///
/// Standing on a row has worked since R10 R2 — the address type, the verb
/// routing and the ↑/↓ nav all landed there — but only through the FRAME
/// side: you could press a lane's band and nothing else. The two halves
/// this bundle adds are what makes it a thing you can see and aim:
///
/// * [currentRow] is drawn. A [ValueListenable] rather than session state
///   read at build time, because the claim that moves the row fires on
///   pointer-DOWN inside gestures whose contract is silence until release
///   — so the rows subscribe and the small cells repaint themselves.
/// * [onStandOnLane] makes the LABEL a place you can stand, the way the
///   layer row's label already selects its layer. It carries no frame:
///   standing is not seeking, and the two surfaces that host these rows
///   count frames differently (the timeline locally, the storyboard
///   globally) — a frame in this signature is a trap, not a feature.
class TimelineCurrentRowHooks {
  const TimelineCurrentRowHooks({required this.currentRow, this.onStandOnLane});

  final ValueListenable<TimelineRowAddress?> currentRow;

  /// Null leaves labels inert (passive hosts, and the test harnesses that
  /// mount a grid without a session).
  final void Function(LayerId layerId, String laneId)? onStandOnLane;
}

/// Whether [row] IS the (layer, lane) property row — the one test every
/// rail surface asks, stated once so a surface cannot invent its own.
bool currentRowIsLane(TimelineRowAddress? row, LayerId layerId, String laneId) {
  return row is LaneRowAddress &&
      row.layerId == layerId &&
      row.laneId == laneId;
}

/// Whether [row] stands on a MEMBER of the group the header [headerLaneId]
/// leads — so a header lights while you are inside it.
///
/// The rail reads as the chain it is: standing on `Radius` lights the
/// layer, its `Blur` header and the property (user, 2026-08-07). All three
/// wear the SAME wash, deliberately — which of them you are actually on is
/// already visible on the frame side, and a second strength here would be
/// one more thing to learn for something already answered.
bool currentRowIsInsideGroup(
  TimelineRowAddress? row,
  LayerId layerId,
  String headerLaneId,
) =>
    row is LaneRowAddress &&
    row.layerId == layerId &&
    laneGroupOf(row.laneId) == headerLaneId;

/// The header lane of the group [laneId] is a MEMBER of, or null — for a
/// header itself, and for a lane in no group (an SE audio lane).
///
/// The membership is the lane-id grammar, which is why it can live in a
/// widget: an effect's members carry its id (`fx:<effectId>:<param>` under
/// `fx-group:<effectId>`), the transform group's members are the named
/// transform lanes — the camera row's included, the row being that group's
/// header (㉙) — and the two fixed groups' carry theirs (`reference:` under
/// the reference fx, `name-tag:` under the name tag; F-374: the reference
/// fx is an fx like every other, and I-68-Q1 made the two one law). The
/// light a header wears while you stand inside it and the graph a header
/// opens over its lanes (I-89 ③) ask it alike.
String? laneGroupOf(String laneId) {
  final effect = parseEffectLaneId(laneId);
  if (effect != null) {
    return effect.parameterId == null
        ? null
        : effectGroupLaneId(effect.effectId);
  }
  if (referenceLaneDisplayOrder.contains(laneId)) {
    return referenceGroupLaneId;
  }
  if (seNameTagLaneDisplayOrder.contains(laneId)) {
    return seNameTagGroupLaneId;
  }
  return transformLaneDisplayOrder.contains(laneId)
      ? transformGroupHeaderLane.laneId
      : null;
}
