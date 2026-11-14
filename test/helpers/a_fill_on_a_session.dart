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
/// pixels — on a project that uses a pasteboard, or none where
/// [pasteboardInUse] is off. A file using it opens the engine first
/// (`opensTheEnginesScreens`).
EditorSessionManager sessionOfRows(
  List<Layer> rows, {
  required CanvasSize canvasSize,
  required Map<(LayerId, FrameId), BitmapSurface> cels,
  required LayerId standOn,
  bool pasteboardInUse = true,
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
      pasteboardInUse: pasteboardInUse,
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
/// on, through the door its canvas asks ([fillRangeOn]) — [at] in the space
/// a canvas hands a press over in: the pose of the row stood on.
FillRange? fillPressedOn(
  EditorSessionManager session,
  CanvasPoint at, {
  FloodFillOptions options = const FloodFillOptions(),
  SymmetryShape? symmetry,
  void Function()? onOpenRegion,
}) {
  final stoodOn = session.editingCanvas.activeBrushEditorSelection?.layerId;
  return fillRangeOn(
    session,
    at,
    options: options,
    space: stoodOn == null
        ? null
        : session.frameVerbs.layerCanvasPoseSample(stoodOn),
    symmetry: symmetry,
    onOpenRegion: onOpenRegion,
  );
}
