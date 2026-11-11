import 'package:flutter/material.dart';

import '../../core/progress_share.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../services/editing/fx_bake_plan.dart' show ReferenceRidersTaking;
import '../../services/reference_move_carried.dart' show ReferenceMoveCarried;
import '../dialogs/app_progress_dialog.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import 'merge_layer_rows.dart' show layBakedPictures;

/// Rasterizes [targets] — the reference rows a press acts on — each the
/// way the coordinator's one answer says (`referenceLetGo`, F-374-Q7), with
/// every other use of its cels (F-374-Q10).
///
/// The rows whose move their own transform carries land at once, in the one
/// undo step they always did. The rest are BAKED — a movie decoded and a
/// still its fx moves or its uses show apart taken a position apiece, a
/// still's cels drawn where the row shows them — so they go behind the one
/// wait window this app shows for heavy work ([runWithAppProgress]) — the
/// window the placement window's bake uses, because it is the same work.
/// ↩️A row whose uses showed its still apart was left the reference it
/// was, and a notice said why (F-374-Q11 「막고 경고」), until 🗣️I-120-Q22
/// parted its cels.
///
/// The press is ONE undo step however its rows let go — the law the keyed
/// rows' one step already kept, asked of the whole press (I-120 ⑥-③, the
/// Surface 2026-11-07: two rows baked, three undos). ↩️Each baked row was
/// a step of its own, or more, until then.
Future<void> rasterizeReferenceRows(
  BuildContext context,
  EditorSessionManager session,
  List<Layer> targets,
) async {
  final cutId = session.activeCutOrNull?.id;
  if (cutId == null) {
    return;
  }
  // The bakes write a row at a time across the wait window's events, so
  // the press folds what it wrote once it is over, as Import's does (F-405)
  // — a batch that stopped part-way is still one press.
  final history = session.historyManager.gestures;
  final pressed = history.mark;
  try {
    await _letGo(context, session, cutId, targets);
  } finally {
    history.foldSince(pressed, 'Rasterize layers');
  }
}

/// [targets] let go, each the way `referenceLetGo` says.
Future<void> _letGo(
  BuildContext context,
  EditorSessionManager session,
  CutId cutId,
  List<Layer> targets,
) async {
  final keyed = <LayerId>[];
  final baked = <_Baked>[];
  for (final layer in targets) {
    switch (session.cutCommandCoordinator.referenceLetGoOf(
      cutId: cutId,
      layerId: layer.id,
    )) {
      // A movie is decoded either way: its door carries the moves first.
      case ReferenceMoveCarried(bakes: false, framed: false):
        keyed.add(layer.id);
      case ReferenceMoveCarried(:final framed):
        baked.add((row: layer, framed: framed));
    }
  }
  if (keyed.isNotEmpty) {
    session.editingCanvas.rasterizeLayerReferences(keyed);
  }
  if (baked.isNotEmpty) {
    await _bake(context, session, cutId, baked);
  }
}

/// A row a rasterize bakes, and whether its cels are made a position apiece
/// ([ReferenceMoveCarried.framed]) or take the picture in place.
typedef _Baked = ({Layer row, bool framed});

/// [baked] rasterized behind the wait window, one bar for the batch.
Future<void> _bake(
  BuildContext context,
  EditorSessionManager session,
  CutId cutId,
  List<_Baked> baked,
) {
  final strings = AppText.strings;
  return runWithAppProgress<void>(
    context: context,
    title: baked.length > 1
        ? strings.tlSelectedLayers
        : baked.single.row.name,
    titleIcon: Icons.texture_outlined,
    runningLabel: strings.bakeProgressRunning,
    windowKey: const ValueKey<String>('reference-rasterize-progress'),
    task: (report) async {
      for (var i = 0; i < baked.length; i += 1) {
        // One bar for the batch: each row fills its own share of it.
        void share(int rendered, int total) => report(
          pieceShare(
            doneShare(rendered, total),
            index: i,
            count: baked.length,
          ),
        );
        final layerId = baked[i].row.id;
        final riders = session.layerMerging.referenceRidersOf(cutId, layerId);
        final bool letGo;
        if (baked[i].framed) {
          letGo = await session.importDoors.rasterizeReferenceFrames(
            cutId: cutId,
            layerId: layerId,
            onRenderProgress: share,
          );
        } else {
          letGo = await session.importDoors.bakeReferenceAsSeen(
            cutId: cutId,
            layerId: layerId,
          );
          share(1, 1);
        }
        if (letGo && riders != null) {
          await _bakeRiders(session, riders);
        }
      }
    },
  );
}

/// The rows riding a row a bake let go of, taken before it did ([riders]),
/// baked wearing the move it let go of — by the rule an fx RASTERIZE bakes
/// its riders by (🗣️attach-rows-lose-the-base-move-when-it-bakes-Q1, 유저
/// 2026-11-11 「어태치 줄도 같이 옮겨 놓는다」 — 「기준fx 구울떄랑
/// 같은규칙으로」): their pictures laid, then their rows landed in the
/// press's one step.
Future<void> _bakeRiders(
  EditorSessionManager session,
  ReferenceRidersTaking riders,
) async {
  final merging = session.layerMerging;
  final plan = merging.planOfReferenceRiders(riders);
  await layBakedPictures(session, plan.pictures, (_) {});
  merging.landReferenceRiders(plan);
}
