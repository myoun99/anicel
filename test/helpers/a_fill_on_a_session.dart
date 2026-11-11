import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/fill_picture_over.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one cel a row made by [drawingRow] exposes over its cut.
const FrameId theCel = FrameId('cel');

/// A drawing row [id] that exposes one cel — [theCel] — over the cut's
/// first frame.
Layer drawingRow(String id) => Layer(
  id: LayerId(id),
  name: id,
  frames: [Frame(id: theCel, duration: 1, strokes: const [])],
  timeline: {0: const TimelineExposure.drawing(theCel, length: 1)},
);

/// A session whose one cut is [canvasSize] and holds [rows] — bottom first —
/// beside the rows every cut is born with, standing on its first
/// frame and on the row [standOn]: each cel named in [cels] storing those
/// pixels. A file using it opens the engine first
/// (`opensTheEnginesScreens`).
EditorSessionManager sessionOfRows(
  List<Layer> rows, {
  required CanvasSize canvasSize,
  required Map<(LayerId, FrameId), BitmapSurface> cels,
  required LayerId standOn,
}) {
  final cut = importedCut(
    defaultCut: createDefaultTrack().cuts.single.copyWith(
      canvasSize: canvasSize,
    ),
    layers: rows,
    duration: 24,
  );
  final session = EditorSessionManager(
    initialProject: createDefaultProject().copyWith(
      tracks: [createDefaultTrack(firstCut: cut)],
    ),
  );
  addTearDown(session.dispose);
  for (final MapEntry(key: (row, cel), value: pixels) in cels.entries) {
    session.renderCaches.brushFrameStore.storeBakedSurface(
      session.brushFrameKeyForCut(cut, row, cel),
      pixels,
    );
  }
  session.selectLayer(standOn);
  return session;
}

/// The range a fill pressed at [at] makes on the frame [session] stands
/// on, asked as its canvas asks it (`_InteractiveCanvasBuild`'s
/// `fillRangeAt`): the picture the canvas's own door reads
/// ([fillPictureOver]) of the session's frame, its read source and the row
/// stood on, in that row's space.
FillRange? fillPressedOn(
  EditorSessionManager session,
  CanvasPoint at, {
  FloodFillOptions options = const FloodFillOptions(),
  SymmetryShape? symmetry,
  void Function()? onOpenRegion,
}) {
  final cut = session.requireActiveCut;
  final stoodOn = session.editingCanvas.activeBrushEditorSelection?.layerId;
  final space = stoodOn == null
      ? null
      : session.frameVerbs.layerCanvasPoseSample(stoodOn);
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
    point: at,
    options: options,
    space: space,
    symmetry: symmetry,
    onOpenRegion: onOpenRegion,
    pasteboardReach: session.repository.requireProject().pasteboardReach,
  );
}
