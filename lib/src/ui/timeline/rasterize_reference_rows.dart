import 'package:flutter/material.dart';

import '../../core/progress_share.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/movie_cel.dart';
import '../../models/timeline_coverage.dart';
import '../../services/reference_move_carried.dart'
    show ReferenceMoveCarried, ReferenceMoveWaits, ReferenceWait;
import '../dialogs/app_confirm_dialog.dart' show NoticeDetails, showAppNotice;
import '../dialogs/app_progress_dialog.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart' show ReferenceWaitWords;

/// How many cels rasterizing [layer] would leave behind.
///
/// A STILL reference's cels are already its own, so it is the cels it
/// holds — a still its transform cannot carry the move of takes it in those
/// same cels (`bakeReferenceAsSeen`). A MOVIE's are not: one held cel
/// stands for every position of its block, and each position becomes a
/// cel — 30 seconds at 24 fps is 720 of them, which is the number the
/// button has to say before it spends that long (유저 2026-09-11:
/// 「래스터라이즈 · N장」).
int rasterizeCelCount(Layer layer) {
  if (!isMovieReference(layer)) {
    return layer.frames.length;
  }
  var positions = 0;
  for (final block in drawingBlocks(layer.timeline)) {
    positions += block.length;
  }
  return positions;
}

/// Rasterizes [targets] — the reference rows a press acts on — each the
/// way the coordinator's one answer says (`referenceLetGo`, F-374-Q7), with
/// every other use of its cels (F-374-Q10).
///
/// The rows whose move their own transform carries land at once, in the one
/// undo step they always did. The rest are BAKED — a movie decoded frame by
/// frame, a still's cels drawn where the row shows them — so they go behind
/// the one wait window this app shows for heavy work ([runWithAppProgress])
/// — the window the placement window's bake uses, because it is the same
/// work. A row that waits is left the reference it is, and says why
/// ([showReferenceWaits]).
Future<void> rasterizeReferenceRows(
  BuildContext context,
  EditorSessionManager session,
  List<Layer> targets,
) async {
  final cutId = session.activeCutOrNull?.id;
  if (cutId == null) {
    return;
  }
  final keyed = <LayerId>[];
  final baked = <Layer>[];
  final waits = <({Layer row, ReferenceWait why})>[];
  for (final layer in targets) {
    switch (session.cutCommandCoordinator.referenceLetGoOf(
      cutId: cutId,
      layerId: layer.id,
    )) {
      case ReferenceMoveWaits(:final why):
        waits.add((row: layer, why: why));
      // A movie is decoded either way: its door carries the moves first.
      case ReferenceMoveCarried(bakes: false) when !isMovieReference(layer):
        keyed.add(layer.id);
      case ReferenceMoveCarried():
        baked.add(layer);
    }
  }
  if (keyed.isNotEmpty) {
    session.editingCanvas.rasterizeLayerReferences(keyed);
  }
  if (baked.isNotEmpty) {
    await _bake(context, session, cutId, baked);
  }
  if (waits.isNotEmpty && context.mounted) {
    await showReferenceWaits(context, waits);
  }
}

/// [baked] rasterized behind the wait window, one bar for the batch.
Future<void> _bake(
  BuildContext context,
  EditorSessionManager session,
  CutId cutId,
  List<Layer> baked,
) {
  final strings = AppText.strings;
  return runWithAppProgress<void>(
    context: context,
    title: baked.length > 1 ? strings.tlSelectedLayers : baked.single.name,
    titleIcon: Icons.texture_outlined,
    runningLabel: strings.bakeProgressRunning,
    doneLabel: strings.bakeProgressDone,
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
        final layerId = baked[i].id;
        if (isMovieReference(baked[i])) {
          await session.importDoors.rasterizeMovieReference(
            cutId: cutId,
            layerId: layerId,
            onRenderProgress: share,
          );
        } else {
          await session.importDoors.bakeReferenceAsSeen(
            cutId: cutId,
            layerId: layerId,
          );
          share(1, 1);
        }
      }
    },
  );
}

/// THE notice a rasterize that left rows the references they are is read
/// in — 🗣️F-374-Q11 (유저 2026-10-17, 「막고 경고」: 「그 두 경우는
/// 래스터라이즈하지 않고 경고로 왜인지 알립니다」): why each waits and what
/// gets it past, said once over every row it was said of.
Future<void> showReferenceWaits(
  BuildContext context,
  List<({Layer row, ReferenceWait why})> waits,
) {
  final named = <ReferenceWait, List<String>>{};
  for (final (:row, :why) in waits) {
    (named[why] ??= []).add(row.name);
  }
  return showAppNotice(
    context,
    windowKey: const ValueKey<String>('reference-rasterize-waits'),
    title: AppText.strings.commonNotice,
    message: AppText.strings.rasterizeLeftReferences,
    details: [
      for (final MapEntry(key: why, value: names) in named.entries)
        NoticeDetails(
          names,
          heading: why.labelFor(AppText.language),
          open: true,
          oneLineEach: true,
        ),
    ],
  );
}

/// The layer menu's RASTERIZE (§6-f): the one verb for every
/// derived-content row, through the one router above.
Future<void> rasterizeActiveRow(
  BuildContext context,
  EditorSessionManager session,
) async {
  final layer = session.activeLayer;
  if (layer == null) {
    return;
  }
  await rasterizeReferenceRows(context, session, [layer]);
}
