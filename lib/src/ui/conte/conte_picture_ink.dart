import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart' show MatrixUtils;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../../core/contain_rect.dart';
import '../../core/convex_clip.dart' show convexIntersection;
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
import '../../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../../models/project_id.dart';
import '../../models/sheet_marks.dart';
import '../../models/track_id.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/camera_projection_matrix.dart';
import '../../services/cut_frame_composite_plan.dart' show layerPlacementAt;
import '../../services/layer_pose_matrix.dart';
import '../canvas/active_stroke_overlay.dart';
import '../sheet/sheet_ink_controller.dart';
import '../sheet/sheet_ink_layer.dart';
import '../sheet_painting.dart' show tracedRoundedRect;
import '../storyboard_layer_policy.dart';

/// What a picture window asks of the project the conte prints — the
/// session's own answers, so the pen and the printed picture read one
/// project: the cut, the cel's key, the camera at a frame and its frame.
typedef ContePictureProject = ({
  Cut? Function(CutId cutId) cutOf,
  BrushFrameKey Function(Cut cut, LayerId layerId, FrameId frameId) celKeyOf,
  CameraPose Function(Cut cut, int frameIndex) cameraPoseOf,
  CanvasSize cameraFrameSize,
  // The cel a picture of a cell with no block draws into, the conte row it
  // is on and the cut the picture draws through — named before it exists
  // (`AutoFrameForStroke.conteCelFor`); null for a cut with a block.
  ({Cut cut, Layer layer, FrameId frameId})? Function(Cut cut) conteCelOf,
  // Why a picture of a cell with no block takes no ink — null while the
  // canvas's 「프레임 자동 생성」 is on and the stroke makes its cel.
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
/// A cell with no block — a cut with no conte row, or a row whose every
/// block is gone — has nothing to draw into yet. Its picture draws as the
/// canvas's 「프레임 자동 생성」 would have it (유저 답 conte-drawing-target-
/// Q2 「토글을 따른다 (캔버스와 한 법)」): into the cel its first stroke
/// makes, through the cut as it will stand — or, with the toggle off, into
/// nothing, refusing the pen as the canvas does
/// ([ContePictureProject.rowRefusal]).
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
/// or, for a cell with no block, the cel its first stroke makes, drawn
/// through the cut `AutoFrameForStroke.conteCelFor` gives.
({Cut cut, Layer layer, FrameId frameId, bool pending})? _drawnOf(
  Cut cut,
  ContePlacedCell cell,
  ContePictureProject project,
) {
  final row = storyboardLayerForCut(cut);
  final frameId = cell.source.frameId;
  if (row != null && frameId != null) {
    return (cut: cut, layer: row, frameId: frameId, pending: false);
  }
  final made = project.conteCelOf(cut);
  if (made == null) {
    return null;
  }
  return (
    cut: made.cut,
    layer: made.layer,
    frameId: made.frameId,
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
  final canvasToPaper = Matrix4.translationValues(shown.left, shown.top, 0)
    ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
    ..multiply(
      cameraProjectionMatrix(project.cameraPoseOf(cut, frame), camera),
    );
  // The cell, not the drawing: a drawing exposed twice is two pictures.
  final id = 'picture-${cell.cutId}-${cell.source.startFrame}';
  return (
    window: SheetPictureWindow(
      id: id,
      key: project.celKeyOf(cut, layer.id, frameId),
      plane: cut.canvasSize,
      slot: mark.slot,
      canvasToPaper: canvasToPaper,
      artworkToCanvas: placement == null
          ? Matrix4.identity()
          : layerPoseMatrix(
              placement.pose,
              cut.canvasSize,
              anchorPoint: placement.anchorPoint,
            ),
      paperOutline: _outlineOf(mark, shown, cut.canvasSize, canvasToPaper),
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

/// What a picture shows of its slot, on the paper — what the sheet clips it
/// to: the slot's rounded corners ([tracedRoundedRect]), the camera's frame
/// in it ([shown]) and the cut's canvas, where [canvasToPaper] lays it. The
/// pen takes exactly this, so a stroke's piece in a corner the picture
/// cuts away stays on the paper that shows it.
List<Offset> _outlineOf(
  SheetPicture mark,
  Rect shown,
  CanvasSize canvas,
  Matrix4 canvasToPaper,
) {
  List<Offset> cornersOf(Rect rect) => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];
  final slot = mark.cornerRadius > 0
      ? tracedRoundedRect(mark.slot, mark.cornerRadius)
      : cornersOf(mark.slot);
  return convexIntersection(convexIntersection(slot, cornersOf(shown)), [
    for (final corner in cornersOf(canvas.canvasRect))
      MatrixUtils.transformPoint(canvasToPaper, corner),
  ]);
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
