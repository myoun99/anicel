import 'package:flutter/material.dart';

import '../../core/progress_share.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../services/reference_move_carried.dart' show ReferenceMoveCarried;
import '../dialogs/app_progress_dialog.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';

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
        if (baked[i].framed) {
          await session.importDoors.rasterizeReferenceFrames(
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
