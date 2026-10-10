import 'package:flutter/widgets.dart';

import '../../core/convex_clip.dart' show convexIntersection;
import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../canvas/outline_clipper.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import 'playback_frame_painter.dart';

/// The camera a run is seen through on the canvas, at the frame it shows:
/// its pose, the frame it projects into, and the view the canvas is seen
/// through — the panel's with that projection under it
/// ([CanvasLook.frameViewThrough]).
typedef CameraShotAt = ({
  CameraPose pose,
  CanvasSize frameSize,
  CanvasViewport frameView,
});

/// A run seen through the camera on the canvas
/// (playback-plays-the-screen-material): [child] — the canvas drawn through
/// the camera — in the camera's frame where the panel's [view] shows it, on
/// the stage's apron, with everything past the frame letterboxed and
/// nothing of the canvas past its own edge (the film shows no pasteboard:
/// 「페이스트보드는 포함 안 시킴」).
///
/// The frame, the letterbox and the apron are the composite view's, painted
/// by its own painter ([PlaybackFramePainter], no paper and no picture of
/// its own); the picture in them is the canvas's rows, not a composite.
/// ↩️A run seen through the camera played on that view, from a composite
/// made for every frame — a second picture of what the canvas holds.
///
/// ⛔THERE WHETHER OR NOT THERE IS A [shot]: without one it paints nothing
/// and cuts nothing. A wrapper that came and went with the camera would
/// mount [child] again — the canvas's stack and every image it holds —
/// whenever the camera view is turned on or off under a run, and at every
/// run's start and end.
class CameraShot extends StatelessWidget {
  const CameraShot({
    super.key,
    required this.view,
    required this.shot,
    required this.canvasSize,
    required this.pasteboardColor,
    required this.pasteboardNone,
    required this.child,
  });

  /// The panel's view — the camera's frame is laid in it.
  final CanvasViewport view;

  /// The camera [child] is seen through — null for a canvas seen through
  /// none.
  final CameraShotAt? shot;

  final CanvasSize canvasSize;

  /// The stage's apron: what the camera sees past the paper. An ABSENT
  /// pasteboard (F-114) is the checkerboard here, as on the editing canvas.
  final Color pasteboardColor;
  final bool pasteboardNone;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shot = this.shot;
    final ratio = EffectiveDevicePixelRatio.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: shot == null
              ? null
              : PlaybackFramePainter(
                  image: null,
                  canvasSize: canvasSize,
                  viewport: view,
                  devicePixelRatio: ratio,
                  cameraPose: shot.pose,
                  cameraFrameSize: shot.frameSize,
                  // The paper is the canvas's own, drawn with its rows.
                  paintPaper: false,
                  pasteboardColor: pasteboardColor,
                  pasteboardNone: pasteboardNone,
                  checkersAbsentPlanes: true,
                ),
        ),
        ClipPath(
          clipBehavior: shot == null ? Clip.none : Clip.antiAlias,
          clipper: shot == null
              ? null
              : OutlineClipper(
                  pictureOutlineOnScreen(view, shot, canvasSize, ratio),
                ),
          child: child,
        ),
      ],
    );
  }
}

/// Where a cut's picture is cut on a screen of [devicePixelRatio]: its
/// canvas's own edge where the panel's [view] shows it — and, seen through
/// a camera ([shot]), inside the camera's frame too, its canvas's edge where
/// the camera puts it. The film shows no pasteboard
/// (「페이스트보드는 포함 안 시킴」), and a cut seen whole shows what its
/// canvas holds.
List<Offset> pictureOutlineOnScreen(
  CanvasViewport view,
  CameraShotAt? shot,
  CanvasSize canvasSize,
  double devicePixelRatio,
) => shot == null
    ? outlineOnScreen(canvasSize.canvasRect, view, devicePixelRatio)
    : convexIntersection(
        cameraFrameOnScreen(view, shot.frameSize, devicePixelRatio),
        outlineOnScreen(canvasSize.canvasRect, shot.frameView, devicePixelRatio),
      );

/// The camera's frame where the panel's [view] lays it on a screen of
/// [devicePixelRatio] — what a run seen through the camera shows, its
/// picture and everything over the picture alike.
List<Offset> cameraFrameOnScreen(
  CanvasViewport view,
  CanvasSize frameSize,
  double devicePixelRatio,
) => outlineOnScreen(frameSize.canvasRect, view, devicePixelRatio);

/// [rect]'s corners where [view] paints them — the pan snapped as every
/// canvas-space painter snaps it ([renderSnappedViewport]), so an outline
/// cut by these lands on the edge the painter drew.
List<Offset> outlineOnScreen(
  Rect rect,
  CanvasViewport view,
  double devicePixelRatio,
) {
  final toScreen = viewportTransformMatrix(
    renderSnappedViewport(view, devicePixelRatio),
  );
  return [
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ])
      MatrixUtils.transformPoint(toScreen, corner),
  ];
}
