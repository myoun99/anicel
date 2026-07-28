import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../canvas/layer_pose_paint.dart';
import '../canvas/paper_background.dart';
import '../canvas/viewport_canvas_transform.dart';

/// Paints one cached composite frame inside the canvas panel viewport.
///
/// Canvas mode ([cameraPose] null) draws the paper and the composite in
/// canvas space under the interactive [viewport] transform — the exact
/// framing the editing canvas uses, so panel zoom/pan keep working during
/// playback. A null [image] paints just the paper (the blank-canvas
/// placeholder reuses this).
///
/// Camera mode looks through the pose instead: the camera's output frame
/// takes the canvas's place under the SAME viewport transform (zoom/pan keep
/// working here too), everything outside it letterboxed dark, and the
/// canvas-space composite is projected with the transform the export
/// renderer uses — no re-render, camera moves are pure GPU transforms over
/// the cached image.
class PlaybackFramePainter extends CustomPainter {
  const PlaybackFramePainter({
    required this.image,
    required this.canvasSize,
    this.viewport,
    this.cameraPose,
    this.cameraFrameSize,
    this.cutPose,
    this.cutAnchorPoint,
    this.fadeOpacity = 1,
    this.imageOpacity = 1,
    this.fadeColor = const Color(0xFF000000),
    this.letterboxColor = const Color(0xFF15191C),
    // R28 #9: the one paper constant, not a repeated literal.
    this.paperColor = const Color(ProjectBackground.defaultPaperArgb),
    this.paperBackground,
    this.paintPaper = true,
    this.paintLetterbox = true,
  }) : assert(
         cameraPose == null || cameraFrameSize != null,
         'Camera mode needs the camera frame size.',
       );

  /// The composite at any cached quality; drawn stretched to canvas size.
  final ui.Image? image;

  final CanvasSize canvasSize;

  /// Pan/zoom of the panel viewport; identity when null.
  final CanvasViewport? viewport;

  /// Non-null = look through the camera.
  final CameraPose? cameraPose;
  final CanvasSize? cameraFrameSize;

  /// The CUT-level pose (the V track's Transform — AE precomp semantics):
  /// the cut's finished picture moves on the DISPLAY space, above the
  /// camera projection. Resolved by cutPoseAt over the same space this
  /// painter draws (camera frame in camera mode, canvas otherwise); null =
  /// identity, zero cost. Display-time only, never baked into composites
  /// (the cut fade's rule). Canvas mode keeps the PAPER static and moves
  /// only the merged content, clipped to the canvas (R7-③: "the canvas
  /// stays put, the contents move as one") — the paper is the panel's
  /// stage, not part of the cut's picture there.
  final TransformPose? cutPose;

  /// The cut pose's anchor; null = the display-space center.
  final CanvasPoint? cutAnchorPoint;

  /// The cut fade (Cut.fadeOpacityAt): paper and composite fade together
  /// toward [fadeColor]. 1 costs nothing.
  final double fadeOpacity;

  /// Alpha on the composite draw itself. The stacked parked view fades a
  /// NON-bottom track through this instead of [fadeOpacity]: the full-
  /// frame fade wash would blank the tracks below, but a track above the
  /// stage fading away should reveal them. 1 costs nothing.
  final double imageOpacity;

  /// What the fade fades TO (cutFadeTargetColor: FO=black, WO=white) — an
  /// overlay at (1 − [fadeOpacity]) over the canvas rect, matching the MP4
  /// bake exactly.
  final Color fadeColor;

  final Color letterboxColor;
  final Color paperColor;

  /// The project background (R10-⑥); when set it wins over [paperColor]
  /// and may render the transparent checkerboard.
  final ProjectBackground? paperBackground;

  /// False = no paper at all (playlist GAPS, UI-R9 #2): the panel's own
  /// background shows through — the same void the gap-parked scrub
  /// preview shows. There is no cut in a gap, so there is no paper.
  final bool paintPaper;

  /// False = camera mode fills nothing outside the frame (stays
  /// transparent). The multitrack stack paints one frame per track: only
  /// the bottom one letterboxes, the ones above composite over it.
  final bool paintLetterbox;

  void _paintPaper(Canvas canvas, Rect rect) {
    if (!paintPaper) {
      return;
    }
    final background = paperBackground;
    if (background != null) {
      paintProjectPaper(canvas, rect, background);
    } else {
      canvas.drawRect(rect, Paint()..color = paperColor);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final pose = cameraPose;

    canvas.save();
    // CustomPaint does not clip: a zoomed/panned frame must never escape the
    // canvas viewport into neighboring panels.
    canvas.clipRect(Offset.zero & size);

    if (pose != null && paintLetterbox) {
      canvas.drawRect(Offset.zero & size, Paint()..color = letterboxColor);
    }
    final resolvedViewport = viewport;
    if (resolvedViewport != null) {
      applyViewportTransform(canvas, resolvedViewport);
    }
    final canvasRect = Rect.fromLTWH(
      0,
      0,
      canvasSize.width.toDouble(),
      canvasSize.height.toDouble(),
    );

    Rect? frameRect;
    if (pose != null) {
      // The camera's output frame takes the canvas's place in viewport
      // space; the projection inside it matches
      // CameraFrameRenderService.renderThroughCamera.
      final frameSize = cameraFrameSize!;
      frameRect = Rect.fromLTWH(
        0,
        0,
        frameSize.width.toDouble(),
        frameSize.height.toDouble(),
      );
      canvas.clipRect(frameRect);
    }
    // The cut pose (AE precomp semantics) transforms the cut's FINISHED
    // picture over the display space — outermost, above the camera
    // projection; the fade overlay below stays a screen dip on top.
    //
    // Canvas mode: the paper draws BEFORE the pose and the moving content
    // clips to it — the canvas is the panel's static stage, only the merged
    // picture moves inside it (R7-③). Camera mode keeps the paper under the
    // pose: there the cut's finished picture (paper included) moves within
    // the output frame, matching the MP4 bake.
    final resolvedCutPose = cutPose;
    if (pose == null) {
      _paintPaper(canvas, canvasRect);
    }
    if (resolvedCutPose != null) {
      canvas.save();
      if (pose == null) {
        canvas.clipRect(canvasRect);
      }
      applyLayerPoseTransform(
        canvas,
        resolvedCutPose,
        pose != null ? cameraFrameSize! : canvasSize,
        anchorPoint: cutAnchorPoint,
      );
    }
    if (pose != null) {
      final frameSize = cameraFrameSize!;
      canvas.save();
      canvas.translate(frameSize.width / 2, frameSize.height / 2);
      canvas.scale(pose.zoom);
      canvas.rotate(-pose.rotationDegrees * math.pi / 180);
      canvas.translate(-pose.center.x, -pose.center.y);
      _paintPaper(canvas, canvasRect);
    }
    final composite = image;
    if (composite != null && imageOpacity > 0) {
      canvas.drawImageRect(
        composite,
        Rect.fromLTWH(
          0,
          0,
          composite.width.toDouble(),
          composite.height.toDouble(),
        ),
        // The dst upscale is what shows Half/Quarter caches at canvas size.
        canvasRect,
        Paint()
          ..filterQuality = FilterQuality.low
          ..color = Color.fromRGBO(0, 0, 0, imageOpacity.clamp(0.0, 1.0)),
      );
    }
    if (pose != null) {
      canvas.restore();
    }
    if (resolvedCutPose != null) {
      canvas.restore();
    }
    if (fadeOpacity < 1) {
      // The picture fades TO the target color (FO=black / WO=white): a
      // plain overlay at (1 − fade) — cheaper than the old saveLayer and
      // it matches the MP4 bake pixel-for-pixel. Camera mode fades the
      // whole output frame (like the bake); canvas mode fades the paper.
      canvas.drawRect(
        frameRect ?? canvasRect,
        Paint()
          ..color = fadeColor.withValues(
            alpha: (1 - fadeOpacity).clamp(0.0, 1.0),
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PlaybackFramePainter oldDelegate) =>
      !identical(oldDelegate.image, image) ||
      oldDelegate.canvasSize != canvasSize ||
      oldDelegate.viewport != viewport ||
      oldDelegate.cameraPose != cameraPose ||
      oldDelegate.cameraFrameSize != cameraFrameSize ||
      oldDelegate.cutPose != cutPose ||
      oldDelegate.cutAnchorPoint != cutAnchorPoint ||
      oldDelegate.fadeOpacity != fadeOpacity ||
      oldDelegate.imageOpacity != imageOpacity ||
      oldDelegate.fadeColor != fadeColor ||
      oldDelegate.letterboxColor != letterboxColor ||
      oldDelegate.paperColor != paperColor ||
      oldDelegate.paperBackground != paperBackground ||
      oldDelegate.paintPaper != paintPaper ||
      oldDelegate.paintLetterbox != paintLetterbox;
}
