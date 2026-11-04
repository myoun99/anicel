import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_id.dart';
import '../../services/editing/fx_bake_plan.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'merge_layer_rows.dart' show bakeAfterAsking;
import 'property_lane_model.dart' show PropertyLaneRow;
import 'transform_lane_policy.dart' show transformGroupHeaderLane;

/// RASTERIZE in [layer]'s group header [lane] (I-120 round ②) as the rail
/// draws it: none where the header is neither an fx's nor the
/// transform's; its press null where it bakes nothing now — 🗣️I-120-Q8
/// 「폴더 · 조정 레이어 둘 다 버튼이 꺼진다」, the slot kept.
({VoidCallback? press})? rasterizeLaneGroupOf(
  BuildContext context,
  EditorSessionManager session,
  Layer layer,
  PropertyLaneRow lane,
) {
  final baked = _bakedBy(lane.laneId);
  if (baked == null) {
    return null;
  }
  return (
    press: session.layerMerging.bakesFx(layer.id, baked.effectId)
        ? () => rasterizeFxGroup(
            context,
            session,
            layer.id,
            baked.effectId,
            lane.label,
          )
        : null,
  );
}

/// The fx a group header's RASTERIZE bakes — the transform's header's,
/// the transform (null) — or none for any other header.
({EffectId? effectId})? _bakedBy(String headerLaneId) {
  if (headerLaneId == transformGroupHeaderLane.laneId) {
    return (effectId: null);
  }
  return switch (parseEffectLaneId(headerLaneId)) {
    (:final effectId, parameterId: null) => (effectId: effectId),
    _ => null,
  };
}

/// RASTERIZE (I-120): [rowId]'s fx [effectId] — the transform, where null —
/// baked into its pictures as they show ([planFxBake]), asked first where
/// the bake changes how the row looks (Q2), with the hatch the reference
/// rasterize's wears (Q10) — a bake ([bakeAfterAsking]).
Future<void> rasterizeFxGroup(
  BuildContext context,
  EditorSessionManager session,
  LayerId rowId,
  EffectId? effectId,
  String name,
) async {
  final plan = session.layerMerging.planOfFx(rowId, effectId);
  if (plan == null) {
    return;
  }
  final strings = AppText.strings;
  await bakeAfterAsking<FxBakeChange>(context, session, (
    title: strings.tlRasterizeFxTemplate.replaceAll('{name}', name),
    icon: Icons.texture_outlined,
    windowKey: 'fx-rasterize-progress',
    question: (
      slug: 'fx-rasterize-changes',
      title: strings.tlFxBakeChangesTitle,
      body: strings.tlFxBakeChangesBody,
      accept: strings.imBake,
    ),
    changes: plan.changes,
    lineOf: (change) => switch (change) {
      FxBakeChange.order => strings.tlFxBakeChangeOrder,
      FxBakeChange.wall => strings.tlMergeChangeWall,
    },
    pictures: plan.pictures,
    land: () => session.layerMerging.landFx(plan),
  ));
}
