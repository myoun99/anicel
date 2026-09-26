import 'dart:ui' show Rect, Size;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../../core/contain_rect.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_history_policy.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/conte/conte_page_marks.dart'
    show conteCameraLabelsOf, contePictureOf;
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project_id.dart';
import '../../models/sheet_marks.dart';
import '../../models/track_id.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/camera_projection_matrix.dart';
import '../../services/cut_frame_composite_plan.dart' show layerPlacementAt;
import '../../services/layer_pose_matrix.dart';
import '../../services/project_repository.dart' show cutWithLayerInserted;
import '../canvas/active_stroke_overlay.dart';
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
  // The conte row a cut with none would be given, and where — named before
  // it exists (`AutoFrameForStroke.conteRowFor`); null for a cut that has
  // its row.
  ({Layer layer, int index})? Function(Cut cut) conteRowOf,
  // Why a picture of a cut with no conte row takes no ink — null while the
  // canvas's 「프레임 자동 생성」 is on and the stroke makes the row.
  String? rowRefusal,
});

/// One picture the conte draws into while its brush is on: the window its
/// pen goes through, and what its live composite is painted from — the
/// cut at the picture's frame with the block's conte layer drawn live, the
/// picture as the page prints it and the camera's labels over it.
typedef ContePicture = ({
  SheetPictureWindow window,
  Cut cut,
  Layer layer,
  int frame,
  SheetPicture mark,
  Rect shown,
  List<SheetMark> labels,
});

/// The pictures of [page] the brush draws into: one per cell, into its
/// block's cel (conte-drawing-target ③). Their windows go ABOVE every ink
/// window, so a cell's band keeps what is drawn around its picture and the
/// cel what is drawn on it.
///
/// A cut with no conte row has no block to draw into yet. Its picture
/// draws as the canvas's 「프레임 자동 생성」 would have it (유저 답
/// conte-drawing-target-Q2 「토글을 따른다 (캔버스와 한 법)」): into the cel
/// of the row its first stroke makes, through the cut as it will stand —
/// or, with the toggle off, into nothing, refusing the pen as the canvas
/// does ([ContePictureProject.rowRefusal]).
///
/// [overlayOf] gives picture `id`'s live stroke, the one its pen draws and
/// its composite paints — held by what holds them both, which lets it go
/// after them.
List<ContePicture> contePictures(
  ContePageLayout page,
  ContePictureProject project,
  ActiveStrokeOverlayModel Function(String id) overlayOf,
) => [
  for (final cell in page.cells) ?_pictureOf(page, cell, project, overlayOf),
];

/// What [cell]'s picture draws into: its block's cel on [cut]'s conte row —
/// or, on a cut with none, the one cel of the row its first stroke makes,
/// in the cut as that row will leave it.
({Cut cut, Layer layer, FrameId frameId, bool pending})? _drawnOf(
  Cut cut,
  ContePlacedCell cell,
  ContePictureProject project,
) {
  if (storyboardLayerForCut(cut) case final layer?) {
    final frameId = cell.source.frameId;
    return frameId == null
        ? null
        : (cut: cut, layer: layer, frameId: frameId, pending: false);
  }
  final row = project.conteRowOf(cut);
  if (row == null) {
    return null;
  }
  return (
    cut: cutWithLayerInserted(cut, row.layer, row.index),
    layer: row.layer,
    frameId: row.layer.frames.single.id,
    pending: true,
  );
}

ContePicture? _pictureOf(
  ContePageLayout page,
  ContePlacedCell cell,
  ContePictureProject project,
  ActiveStrokeOverlayModel Function(String id) overlayOf,
) {
  final found = project.cutOf(CutId(cell.cutId));
  final drawn = found == null ? null : _drawnOf(found, cell, project);
  if (drawn == null) {
    return null;
  }
  final (:cut, :layer, :frameId, :pending) = drawn;
  final frame = cell.source.pictureFrame;
  final camera = project.cameraFrameSize;
  final mark = contePictureOf(cell, page.metrics);
  // Laid as the sheet lays the picture: the camera's frame contained in
  // the slot (`paintSheetImageContained`).
  final shown = containRect(
    Size(camera.width.toDouble(), camera.height.toDouble()),
    mark.slot,
  );
  final scale = shown.width / camera.width;
  final placement = layerPlacementAt(cut: cut, layer: layer, frameIndex: frame);
  // The cell, not the drawing: a drawing exposed twice is two pictures.
  final id = 'picture-${cell.cutId}-${cell.source.startFrame}';
  return (
    window: SheetPictureWindow(
      id: id,
      key: project.celKeyOf(cut, layer.id, frameId),
      plane: cut.canvasSize,
      slot: mark.slot,
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
      overlay: overlayOf(id),
      refusal: pending ? project.rowRefusal : null,
    ),
    cut: cut,
    layer: layer,
    frame: frame,
    mark: mark,
    shown: shown,
    labels: [...conteCameraLabelsOf(cell, page.metrics)],
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
