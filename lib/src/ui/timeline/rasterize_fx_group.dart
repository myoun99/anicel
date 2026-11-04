import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_id.dart';
import '../../services/editing/fx_bake_plan.dart';
import '../dialogs/app_confirm_dialog.dart' show showAppNotice;
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'layer_reference_popover.dart' show layerReferenceTargets;
import 'merge_layer_rows.dart' show bakeBehindTheWaitWindow;
import 'property_lane_model.dart' show PropertyLaneRow;
import 'rasterize_reference_rows.dart' show rasterizeReferenceRows;
import 'reference_lane_policy.dart' show referenceGroupLaneId;
import 'transform_lane_policy.dart' show transformGroupHeaderLane;

/// RASTERIZE in [layer]'s group header [lane] (I-120 round ②) as the rail
/// draws it: none where the header is neither an fx's, the transform's nor
/// the reference's; its press null where it bakes nothing now —
/// 🗣️I-120-Q8 「폴더 · 조정 레이어 둘 다 버튼이 꺼진다」, the slot kept.
({VoidCallback? press})? rasterizeLaneGroupOf(
  BuildContext context,
  EditorSessionManager session,
  Layer layer,
  PropertyLaneRow lane,
) {
  if (lane.laneId == referenceGroupLaneId) {
    return _referenceRasterize(context, session, layer);
  }
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
            band: switch (session.laneVerbs.groupSpan(layer.id, lane.laneId)) {
              null => null,
              final span => (
                start: span.startIndex,
                end: span.endIndexExclusive,
              ),
            },
          )
        : null,
  );
}

/// 🗣️I-120-Q11 (유저 2026-11-04 「래스터라이즈 버튼만 둔다(지금 참조
/// 래스터라이즈와 같은 길), 스위치는 없음」): the reference header's
/// RASTERIZE is the reference popover's 「래스터라이즈 · N장」 — the rows a
/// press on [layer] acts on ([layerReferenceTargets]), rasterized the one
/// way ([rasterizeReferenceRows]); lit off where it acts on none.
({VoidCallback? press}) _referenceRasterize(
  BuildContext context,
  EditorSessionManager session,
  Layer layer,
) => (
  press: layerReferenceTargets(session, layer.id).isEmpty
      ? null
      : () => unawaited(
          rasterizeReferenceRows(
            context,
            session,
            layerReferenceTargets(session, layer.id),
          ),
        ),
);

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
/// and the chain up to its line baked into its pictures as they show
/// ([planFxBake]) over the frames of the [band] scoping the press, every
/// frame where none does (Q3), asked nothing first (Q21 「경고 창을
/// 없앤다」), with the hatch the reference rasterize's wears (Q10) — a bake
/// ([bakeBehindTheWaitWindow]), saying after which rows it made free
/// (Q18). ↩️One its pictures could not hold in one cel the uses share
/// baked nothing and said why, until Q20 parted the cel.
Future<void> rasterizeFxGroup(
  BuildContext context,
  EditorSessionManager session,
  LayerId rowId,
  EffectId? effectId,
  String name, {
  BakedFrames? band,
}) async {
  if (session.layerMerging.planOfFx(rowId, effectId, band: band)
      case final plan?) {
    await _bake(context, session, plan, name);
  }
}

/// [plan] baked — and, where it made rows free on timings of their own
/// ([FxBakePlan.freed]), a notice saying so after: a change of the rows'
/// make (🗣️I-120-Q20, 유저 2026-11-05 「행 구조가 바뀌는건 안내문」).
Future<void> _bake(
  BuildContext context,
  EditorSessionManager session,
  FxBakePlan plan,
  String name,
) async {
  final strings = AppText.strings;
  var landed = false;
  await bakeBehindTheWaitWindow(context, session, (
    title: strings.tlRasterizeFxTemplate.replaceAll('{name}', name),
    icon: Icons.texture_outlined,
    windowKey: 'fx-rasterize-progress',
    pictures: plan.pictures,
    land: () => landed = session.layerMerging.landFx(plan),
  ));
  if (!landed || plan.freed.isEmpty || !context.mounted) {
    return;
  }
  await showAppNotice(
    context,
    windowKey: const ValueKey<String>('fx-rasterize-rows-freed'),
    title: strings.commonNotice,
    message: strings.tlFxBakeRowsFreedTemplate.replaceAll(
      '{names}',
      plan.freed.join(', '),
    ),
  );
}
