import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_id.dart';
import '../../services/editing/fx_bake_plan.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_progress_dialog.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'merge_layer_rows.dart' show layBakedPictures;
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
/// the bake changes how the row looks (Q2), behind the one wait window
/// heavy work shows ([runWithAppProgress]) with the hatch the reference
/// rasterize's wears (Q10), and landed as one undo step.
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
  if (plan.changes.isNotEmpty &&
      await _accepts(context, plan.changes) != true) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final strings = AppText.strings;
  await runWithAppProgress<void>(
    context: context,
    title: strings.tlRasterizeFxTemplate.replaceAll('{name}', name),
    titleIcon: Icons.texture_outlined,
    runningLabel: strings.bakeProgressRunning,
    doneLabel: strings.bakeProgressDone,
    windowKey: const ValueKey<String>('fx-rasterize-progress'),
    task: (report) async {
      await layBakedPictures(session, plan.pictures, report);
      session.layerMerging.landFx(plan);
    },
  );
}

/// Whether the bake goes ahead over the [changes] it makes to how the row
/// looks — null for a window walked away from.
Future<bool?> _accepts(BuildContext context, Set<FxBakeChange> changes) {
  final strings = AppText.strings;
  return askConfirm(
    context,
    ConfirmQuestion(
      keys: confirmDialogKeys('fx-rasterize-changes'),
      title: strings.tlFxBakeChangesTitle,
      message: strings.tlFxBakeChangesBody,
      titleIcon: Icons.texture_outlined,
      details: [
        NoticeDetails(heading: strings.tlMergeChanges, open: true, [
          for (final change in FxBakeChange.values)
            if (changes.contains(change))
              switch (change) {
                FxBakeChange.order => strings.tlFxBakeChangeOrder,
                FxBakeChange.wall => strings.tlMergeChangeWall,
              },
        ]),
      ],
    ),
    accept: ConfirmChoice(strings.imBake),
  );
}
