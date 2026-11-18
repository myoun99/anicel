import 'package:gpu_engine/gpu_engine.dart' show GpuFloodPicture;

import '../../models/canvas_point.dart';
import '../../models/cut.dart';
import '../../models/dirty_region.dart';
import '../../models/drawing_guide.dart' show SymmetryShape;
import '../../models/layer_id.dart';
import '../../native/app_gpu_engine.dart' show FrameKernelsToCome;
import '../../services/canvas_flood_fill.dart';
import '../../services/canvas_read_source.dart';
import '../../services/cut_frame_composite_plan.dart' show rowAsRead;
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../editor_session_manager.dart';
import '../session/editing_canvas.dart';
import 'frame_pictures.dart';

/// The range a fill pressed at [point] makes on the frame [session] stands
/// on ([fillRangeAt]): its cut's frame read by the fill's read source and
/// the row stood on ([fillPictureOver]) — the 「현재」 of that source is the
/// layer the eyedropper's reads (I-36) —, the apron as far as the project's
/// pasteboard reaches (I-109), in [space]: the space [point] is in, the
/// artwork of the row the dab lands on where that is posed. The picture is
/// read in the space the seed arrives in, and the symmetry's copies are
/// made in it: one [space], handed on to both.
///
/// ⛔ONE DOOR, a canvas's and a test's that presses a fill on a session: a
/// test that spelled the canvas's call again pinned its own spelling
/// (mutants FD23 · FD25 lived, 2026-11-12).
FillRange? fillRangeOn(
  EditorSessionManager session,
  CanvasPoint point, {
  required FloodFillOptions options,
  required LayerPlacement? space,
  double opacity = 1.0,
  SymmetryShape? symmetry,
  void Function()? onOpenRegion,
}) {
  final cut = session.requireActiveCut;
  return fillRangeAt(
    canvasSize: cut.canvasSize,
    pictureOver: (box) => fillPictureOver(
      box,
      pictures: session.playbackRig.framePictures,
      canvas: session.editingCanvas,
      cut: cut,
      frameIndex: session.currentFrameIndex,
      source: options.source,
      activeLayerId: session.activeLayer?.id,
      space: space,
    ),
    point: point,
    opacity: opacity,
    options: options,
    space: space,
    symmetry: symmetry,
    onOpenRegion: onOpenRegion,
    pasteboardReach: session.repository.requireProject().pasteboardReach,
  );
}

/// The picture a fill pressed on [cut]'s frame [frameIndex] reads over
/// [box] of the space its seed is in (`FillPictureOver`) — the canvas, or
/// [space], the artwork of the row the dab lands on where that is posed:
/// the frame as the canvas shows it standing still, drawn of its cels as
/// they are stored now ([FramePictures.drawingNow]), kept on the engine
/// ([fillPictureOf]). Null where there is none to read now: no engine, or a
/// frame whose effect chains' kernels are still to be compiled — one the
/// canvas does not show yet either ([FrameKernelsToCome]).
///
/// 🚨NO PAPER UNDER IT (board F-416, 🗣️유저 2026-10-20: 「레이어에 그린것도
/// 흰색일때 … 캔버스 전체를 칠해버리는거같음. 그림부분만 칠해야하는데」): the
/// paper is not drawn, so a fill neither stops at it nor runs through it
/// into what is drawn its colour. ↩️It was 「fill what you see」 — the layers
/// over the project's paper (R10-C, 07-12; an absent paper read as black
/// since 09-15) — and ink of the paper's colour was the paper: a fill on
/// white ink on a white paper took the whole canvas, and with the fill
/// past the canvas on, a white shape running onto the pasteboard flooded
/// to the wall and was refused as open. Nor a ghost of the onion: a ghost
/// is editing scaffolding, and walls nothing.
///
/// WHICH rows is [source]'s answer, the one the eyedropper reads by too
/// (I-36): every row as the frame shows them — a letter bounds a fill as a
/// drawn line does (🗣️유저 2026-10-06: 「셀의 그림이랑 정확히 동일」), and a
/// row that clips to the one below walls it where it shows, where its base
/// is (I-92) —, or [activeLayerId]'s alone, as a chain that reads a row
/// reads it ([rowAsRead]): as it draws by itself, where it lies, on
/// nothing.
///
/// ⚠️COMPOSITED WHOLE AT EACH ASK (🔬the cost is on the fill's card). ↩️It
/// was composed tile by tile as the flood reached them (R11-③: an eager
/// full-canvas compose on the CPU froze the tap for seconds on big
/// canvases); on the GPU the whole frame is one run of the executor.
GpuFloodPicture? fillPictureOver(
  DirtyRegion box, {
  required FramePictures pictures,
  required EditingCanvas canvas,
  required Cut cut,
  required int frameIndex,
  required CanvasReadSource source,
  required LayerId? activeLayerId,
  required LayerPlacement? space,
}) {
  final tools = pictures.store.toolsOpen;
  if (tools == null) {
    return null;
  }
  final shown = (
    cut: cut,
    frameIndex: frameIndex,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final nodes = switch (layersReadBy(source, activeLayerId)) {
    null => pictures.stackOf(shown),
    final read => [
      for (final row in read)
        ...?switch (rowAsRead(cut: cut, row: row, frameIndex: frameIndex)) {
          final rows? => canvas.stackOfRows(cut, frameIndex, rows),
          null => null,
        },
    ],
  };
  try {
    return fillPictureOf(
      // A cel that cannot be read is drawn without, as the canvas shows the
      // frame — which said why when it drew it.
      pictures.drawingNow(nodes, shown).frame,
      tools.composite,
      tools.letters,
      box,
      space: space,
      // What the frame's chains put for the canvas is what they put here.
      holds: pictures.heldNodes,
    );
  } on FrameKernelsToCome {
    return null;
  }
}
