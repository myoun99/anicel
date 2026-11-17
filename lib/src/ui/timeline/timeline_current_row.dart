import 'package:flutter/foundation.dart' show ValueListenable, VoidCallback;

import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
import 'effect_lane_policy.dart' show effectGroupLaneId, parseEffectLaneId;
import 'reference_lane_policy.dart'
    show referenceGroupLaneId, referenceLaneDisplayOrder;
import 'se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId, seNameTagLaneDisplayOrder;
import 'se_sound_lane_policy.dart'
    show seSoundGroupLaneId, seSoundLaneDisplayOrder;
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
  const TimelineCurrentRowHooks({
    required this.currentRow,
    this.onStandOnLane,
    this.onSettledPress,
  });

  final ValueListenable<TimelineRowAddress?> currentRow;

  /// Null leaves labels inert (passive hosts, and the test harnesses that
  /// mount a grid without a session).
  ///
  /// It runs on the PRESS, as the layer row's label picks (T10, 유저
  /// 2026-08-14 「행이든 뭐든 동일하게」): 🗣️F-476 (유저 2026-10-26 「보통
  /// 레이어 선택범위 작동할땐 그 레이어에 서고나서 선택범위 적용되는데 지금
  /// fx에는 서는게 안됨」). ↩️It ran on the release, which a sweep never
  /// reaches — T10 moved the cells, the sheet and the layer row, and missed
  /// the lane's label.
  final void Function(LayerId layerId, String laneId)? onStandOnLane;

  /// The release of a label press that turned out to be a tap — the
  /// layer row's `onSettledPress`, T10's other half: 「클릭하고 떼면 뭐든
  /// 비우게」.
  final VoidCallback? onSettledPress;
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
    laneIsInGroup(row.laneId, headerLaneId);

/// The header lane of the group [laneId] is a MEMBER of on a row of
/// [kind], or null — for a header itself, and for a lane in no group.
///
/// The membership is the lane-id grammar, which is why it can live in a
/// widget: an effect's members carry its id (`fx:<effectId>:<param>` under
/// `fx-group:<effectId>`), the transform's are the named transform lanes —
/// the camera row's included, the row being that group's header (㉙) — and
/// the fixed groups' carry theirs (`reference:` under the reference fx,
/// `name-tag:` under the name tag, `sound:` under the 「오디오」 group,
/// I-140; F-374: the reference fx is an fx like every other, and I-68-Q1
/// made the two one law). The light a header wears while you stand inside
/// it and the graph a header opens over its lanes (I-89 ③) ask it alike.
///
/// The one word the grammar leaves to the row is a transform lane's
/// group: an S row's name tag, whose pose it is
/// (🗣️audio-fx-grows-like-the-pros-Q3 · Q4), every other row's Transform.
String? laneGroupOf(String laneId, {required LayerKind kind}) =>
    transformLaneDisplayOrder.contains(laneId)
    ? _poseGroupOf(kind)
    : _fixedGroupOf(laneId);

/// Whether [laneId] is a MEMBER of the group [headerLaneId] leads, on the
/// row that draws that header: [laneGroupOf] of the kinds of row there
/// are, a header standing on its own kind's rows alone — no S row draws a
/// Transform group, and no other row a name tag.
bool laneIsInGroup(String laneId, String headerLaneId) =>
    transformLaneDisplayOrder.contains(laneId)
    ? LayerKind.values.map(_poseGroupOf).contains(headerLaneId)
    : _fixedGroupOf(laneId) == headerLaneId;

/// The group a [kind] row's transform lanes stand in ([laneGroupOf]).
String _poseGroupOf(LayerKind kind) => kind == LayerKind.se
    ? seNameTagGroupLaneId
    : transformGroupHeaderLane.laneId;

/// The group of a lane that is no transform lane, by its id alone.
String? _fixedGroupOf(String laneId) {
  final effect = parseEffectLaneId(laneId);
  if (effect != null) {
    return effect.parameterId == null
        ? null
        : effectGroupLaneId(effect.effectId);
  }
  if (referenceLaneDisplayOrder.contains(laneId)) {
    return referenceGroupLaneId;
  }
  if (seSoundLaneDisplayOrder.contains(laneId)) {
    return seSoundGroupLaneId;
  }
  return seNameTagLaneDisplayOrder.contains(laneId)
      ? seNameTagGroupLaneId
      : null;
}
