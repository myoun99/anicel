import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/convex_clip.dart' show convexIntersection, convexOutset;
import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../../models/project_background.dart';
import '../canvas/display_resample.dart'
    show
        displayEdgeAntiAliased,
        displayLevelOf,
        displayScaleOf,
        rectOutwardOnGrid,
        wholeLevelPixelsOutward;
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
    required this.background,
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

  /// The project's paper: [child]'s own, drawn with its rows — laid here
  /// only where it is ABSENT (F-114), as the checkerboard in its place.
  final ProjectBackground background;

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
                  canvasSize: canvasSize,
                  viewport: view,
                  devicePixelRatio: ratio,
                  cameraPose: shot.pose,
                  cameraFrameSize: shot.frameSize,
                  // The paper is the canvas's own, drawn with its rows;
                  // here is only its plane where it is ABSENT — the
                  // checkerboard, as the film lays it through the camera.
                  // ↩️Nothing was laid, so the apron showed in the paper's
                  // place on a cut's run and the checkerboard on the film.
                  paperBackground: background,
                  paintPaper: background.none,
                  pasteboardColor: pasteboardColor,
                  pasteboardNone: pasteboardNone,
                  checkersAbsentPlanes: true,
                ),
        ),
        ShotClip(
          outline: pictureOutlineOnScreen(view, shot, canvasSize, ratio),
          child: child,
        ),
      ],
    );
  }
}

/// [child] cut to [outline] as a run is cut ([shotClipOnScreen]) — and cut
/// nowhere without one: a cut seen through no camera shows what its canvas
/// shows, past its edge too.
///
/// ⛔THERE EITHER WAY, for [CameraShot]'s reason: a clip that came and went
/// with the camera would mount [child] again.
class ShotClip extends StatelessWidget {
  const ShotClip({super.key, required this.outline, required this.child});

  /// Where on the screen [child] is cut — null where nothing is.
  final List<Offset>? outline;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final outline = this.outline;
    final cut = outline == null
        ? null
        : shotClipOnScreen(outline, EffectiveDevicePixelRatio.of(context));
    return ClipPath(
      clipBehavior: cut?.behavior ?? Clip.none,
      clipper: cut == null ? null : OutlineClipper(cut.corners),
      child: child,
    );
  }
}

/// How a run on a screen of [devicePixelRatio] is cut to [outline]
/// ([pictureOutlineOnScreen], [cameraFrameOnScreen]): out to the whole
/// device pixels around it, so the cut falls on no pixel the picture
/// covers in part — that pixel is the picture's, drawn by the law the
/// canvas draws its own edge by ([displayEdgeAntiAliased]).
///
/// 🚨playback-picture-is-not-the-canvas-picture (유저 10-13: 「재생하면
/// 미묘하게 화면 움직이는데 … 배율따라서 끝에 흰 선」): cut ON the outline
/// and anti-aliased, a pixel the canvas covers in part was thinned a second
/// time over what lies past it — along every edge not on a whole pixel,
/// the right and the bottom at most zooms, all four once the pan's phase
/// is in. What the cut lets through instead is less than a pixel past the
/// outline, which the canvas standing still shows whole.
///
/// A turned outline has no whole pixels to grow to: each of its edges goes
/// out a pixel's diagonal, past every pixel the edge crossed, and stays
/// anti-aliased.
({List<Offset> corners, Clip behavior}) shotClipOnScreen(
  List<Offset> outline,
  double devicePixelRatio,
) {
  final square = _squareBounds(outline);
  if (square != null) {
    final whole = rectOutwardOnGrid(square, devicePixelRatio);
    return (
      corners: [
        whole.topLeft,
        whole.topRight,
        whole.bottomRight,
        whole.bottomLeft,
      ],
      behavior: Clip.hardEdge,
    );
  }
  return (
    corners: convexOutset(outline, math.sqrt2 / devicePixelRatio),
    behavior: Clip.antiAlias,
  );
}

/// [outline]'s bounds when every edge of it runs level or plumb — a rect,
/// for a convex outline — or null.
Rect? _squareBounds(List<Offset> outline) {
  if (outline.length < 3) {
    return null;
  }
  const flat = 1e-6;
  for (var index = 0; index < outline.length; index += 1) {
    final along = outline[(index + 1) % outline.length] - outline[index];
    if (along.dx.abs() > flat && along.dy.abs() > flat) {
      return null;
    }
  }
  var bounds = Rect.fromPoints(outline.first, outline.first);
  for (final corner in outline.skip(1)) {
    bounds = bounds.expandToInclude(Rect.fromPoints(corner, corner));
  }
  return bounds;
}

/// Where a cut's picture is cut on a screen of [devicePixelRatio] — seen
/// through a camera ([shot]), at its canvas's edge where the camera puts it
/// inside the camera's frame: the film shows no pasteboard
/// (「페이스트보드는 포함 안 시킴」). Seen through none, nowhere (null): a cut
/// played whole shows what the canvas shows standing still, past its edge
/// too (conte-playback-hides-the-pasteboard, 유저 10-13 「둘 다 보인다(편집
/// 캔버스처럼)」). ↩️The film cut there at the canvas's edge while a cut's run
/// on the canvas did not — the same question, two answers.
List<Offset>? pictureOutlineOnScreen(
  CanvasViewport view,
  CameraShotAt? shot,
  CanvasSize canvasSize,
  double devicePixelRatio,
) => shot == null
    ? null
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

/// [rect]'s corners where [view] paints it — the pan snapped as every
/// canvas-space painter snaps it ([renderSnappedViewport]), so an outline
/// cut by these lands on the edge the painter drew; and out to the grid of
/// the level the display draws at ([wholeLevelPixelsOutward]), where a
/// picture of [rect] ends: a level pixel its edge cuts part-way is drawn
/// whole, box-filtered from the part inside — a run cut on [rect] itself
/// thinned what the canvas standing still shows of it
/// (playback-picture-is-not-the-canvas-picture).
List<Offset> outlineOnScreen(
  Rect rect,
  CanvasViewport view,
  double devicePixelRatio,
) {
  final drawn = wholeLevelPixelsOutward(
    rect,
    displayLevelOf(displayScaleOf(view.zoom, devicePixelRatio)),
  );
  final toScreen = viewportTransformMatrix(
    renderSnappedViewport(view, devicePixelRatio),
  );
  return [
    for (final corner in [
      drawn.topLeft,
      drawn.topRight,
      drawn.bottomRight,
      drawn.bottomLeft,
    ])
      MatrixUtils.transformPoint(toScreen, corner),
  ];
}
