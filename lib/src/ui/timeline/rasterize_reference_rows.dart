import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/movie_cel.dart';
import '../../models/timeline_coverage.dart';
import '../dialogs/app_progress_dialog.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';

/// How many cels rasterizing [layer] would leave behind.
///
/// A STILL reference's cels are already its own, so it is the cels it
/// holds. A MOVIE's are not: one held cel stands for every position of its
/// block, and each position becomes a cel — 30 seconds at 24 fps is 720 of
/// them, which is the number the button has to say before it spends that
/// long (유저 2026-09-11: 「래스터라이즈 · N장」).
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

/// Rasterizes [targets] — the reference rows a press acts on.
///
/// The rows whose pixels are already their cels land at once, in the one
/// undo step they always did. A MOVIE is decoded frame by frame, so it goes
/// behind the one wait window this app shows for heavy work
/// ([runWithAppProgress]) — the window the placement window's bake uses,
/// because it is the same work.
Future<void> rasterizeReferenceRows(
  BuildContext context,
  EditorSessionManager session,
  List<Layer> targets,
) async {
  final movies = [
    for (final layer in targets)
      if (isMovieReference(layer)) layer,
  ];
  final stills = [
    for (final layer in targets)
      if (!isMovieReference(layer)) layer.id,
  ];
  if (stills.isNotEmpty) {
    session.editingCanvas.rasterizeLayerReferences(stills);
  }
  final cutId = session.activeCutOrNull?.id;
  if (movies.isEmpty || cutId == null) {
    return;
  }
  final strings = AppText.strings;
  await runWithAppProgress<void>(
    context: context,
    title: movies.length > 1 ? strings.tlSelectedLayers : movies.single.name,
    titleIcon: Icons.texture_outlined,
    runningLabel: strings.bakeProgressRunning,
    doneLabel: strings.bakeProgressDone,
    windowKey: const ValueKey<String>('movie-rasterize-progress'),
    task: (report) async {
      for (var i = 0; i < movies.length; i += 1) {
        await session.importDoors.rasterizeMovieReference(
          cutId: cutId,
          layerId: movies[i].id,
          // One bar for the batch: each row fills its own share of it.
          onRenderProgress: (rendered, total) => report(
            total <= 0 ? 1 : (i + rendered / total) / movies.length,
          ),
        );
      }
    },
  );
}

/// The layer menu's RASTERIZE (§6-f): the one verb for every
/// derived-content row. A still reference is the session's own — nothing
/// to decode — and a movie reference goes through the wait window above.
Future<void> rasterizeActiveRow(
  BuildContext context,
  EditorSessionManager session,
) async {
  final layer = session.activeLayer;
  if (layer == null) {
    return;
  }
  if (!isMovieReference(layer)) {
    session.editingCanvas.rasterizeActiveLayer();
    return;
  }
  await rasterizeReferenceRows(context, session, [layer]);
}
