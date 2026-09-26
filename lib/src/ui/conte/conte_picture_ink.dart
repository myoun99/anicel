import 'dart:ui' show Size;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../../core/contain_rect.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_history_policy.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/conte/conte_page_marks.dart' show contePictureSlot;
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/project_id.dart';
import '../../models/track_id.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/camera_projection_matrix.dart';
import '../../services/cut_frame_composite_plan.dart' show layerPlacementAt;
import '../../services/layer_pose_matrix.dart';
import '../sheet/sheet_ink_controller.dart';
import '../sheet/sheet_ink_layer.dart';
import '../storyboard_layer_policy.dart';

/// What a picture window asks of the project the conte prints — the
/// session's own answers, so the pen and the printed picture read one
/// project: the cut, the cel's key, the camera at a frame and its frame.
typedef ContePictureProject = ({
  Cut? Function(CutId cutId) cutOf,
  BrushFrameKey Function(Cut cut, LayerId layerId, FrameId frameId) celKeyOf,
  CameraPose Function(Cut cut, int frameIndex) cameraPoseOf,
  CanvasSize cameraFrameSize,
});

/// The picture windows of [page]: one per cell whose drawing block has a
/// cel, drawing into it (conte-drawing-target ③). They go ABOVE every ink
/// window, so a cell's band keeps what is drawn around its picture and the
/// cel what is drawn on it.
///
/// A cell with no drawing — a cut with no conte layer, a gap in one — has
/// no cel to draw into yet; what a stroke there makes is
/// conte-picture-autocreate's question, still open.
List<SheetPictureWindow> contePictureWindows(
  ContePageLayout page,
  ContePictureProject project,
) => [
  for (final cell in page.cells) ?_pictureWindowOf(page, cell, project),
];

SheetPictureWindow? _pictureWindowOf(
  ContePageLayout page,
  ContePlacedCell cell,
  ContePictureProject project,
) {
  final frameId = cell.source.frameId;
  final cut = project.cutOf(CutId(cell.cutId));
  final layer = cut == null ? null : storyboardLayerForCut(cut);
  if (frameId == null || cut == null || layer == null) {
    return null;
  }
  final frame = cell.source.pictureFrame;
  final camera = project.cameraFrameSize;
  final slot = contePictureSlot(cell, page.metrics);
  // Laid as the sheet lays the picture: the camera's frame contained in
  // the slot (`paintSheetImageContained`).
  final shown = containRect(
    Size(camera.width.toDouble(), camera.height.toDouble()),
    slot,
  );
  final scale = shown.width / camera.width;
  final placement = layerPlacementAt(cut: cut, layer: layer, frameIndex: frame);
  return SheetPictureWindow(
    // The cell, not the drawing: a drawing exposed twice is two pictures.
    id: 'picture-${cell.cutId}-${cell.source.startFrame}',
    key: project.celKeyOf(cut, layer.id, frameId),
    plane: cut.canvasSize,
    slot: slot,
    canvasToPaper: Matrix4.translationValues(shown.left, shown.top, 0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(
        cameraProjectionMatrix(project.cameraPoseOf(cut, frame), camera),
      ),
    artworkToCanvas: placement == null
        ? Matrix4.identity()
        : layerPoseMatrix(
            placement.pose,
            cut.canvasSize,
            anchorPoint: placement.anchorPoint,
          ),
    canvasSize: cut.canvasSize,
  );
}

/// The cels the conte's pictures draw into: the SESSION's cel store,
/// through a coordinator of its own per canvas size — a cut's canvas may
/// differ from the one the canvas panel stands on, and a coordinator holds
/// one. The plane of a picture window is its cel's canvas size.
///
/// ⛔It selects nothing on the canvas: its coordinators are its own, and
/// the canvas's sessions follow the store rather than whoever wrote it
/// (`BrushFrameEditingCoordinator._storeMovedPast`).
class ContePictureInkController extends SheetInkController<CanvasSize> {
  ContePictureInkController({required BrushFrameStore cels})
    : _cels = cels,
      super(const {}) {
    cels.celPixelRevision.addListener(notifyListeners);
  }

  final BrushFrameStore _cels;

  final Map<CanvasSize, BrushFrameEditingCoordinator> _coordinators = {};

  /// Where a coordinator stands before its first cel is selected — never a
  /// cel of the project, and never written: every read and commit selects
  /// the window's own cel first.
  static const BrushFrameKey _standing = BrushFrameKey(
    projectId: ProjectId('conte-picture'),
    trackId: TrackId('conte-picture'),
    cutId: CutId('conte-picture'),
    layerId: LayerId('conte-picture'),
    frameId: FrameId('conte-picture'),
  );

  @override
  BrushFrameEditingCoordinator coordinatorFor(CanvasSize plane) =>
      _coordinators.putIfAbsent(
        plane,
        () => BrushFrameEditingCoordinator(
          initialFrameKey: _standing,
          frameStore: _cels,
          sessionStore: BrushFrameEditSessionStore(canvasSize: plane),
          historyPolicy: const BrushHistoryPolicy(),
        ),
      );

  @override
  BrushFrameStore storeFor(CanvasSize plane) => _cels;

  @override
  void dispose() {
    _cels.celPixelRevision.removeListener(notifyListeners);
    super.dispose();
  }
}
