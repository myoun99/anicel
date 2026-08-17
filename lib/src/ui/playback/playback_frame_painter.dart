import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../../services/se_name_tag_plan.dart';
import '../canvas/composite_effect_paint.dart' show CompositeEffectPaint;
import '../canvas/display_resample.dart';
import '../canvas/layer_pose_paint.dart';
import '../canvas/paper_background.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../text/se_name_tag_paint.dart';

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
    this.cutEffects = CompositeEffectPaint.none,
    this.fadeOpacity = 1,
    this.imageOpacity = 1,
    this.letterboxColor = const Color(0xFF15191C),
    // R28 #9: the one paper constant, not a repeated literal.
    this.paperColor = const Color(ProjectBackground.defaultPaperArgb),
    this.paperBackground,
    this.pasteboardColor,
    this.paintPaper = true,
    this.paintLetterbox = true,
    this.seNameTags = const [],
    this.devicePixelRatio = 1.0,
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

  /// A pose for the FINISHED picture on the DISPLAY space, above the camera
  /// projection (AE precomp semantics): null = identity, zero cost.
  /// Display-time only, never baked into composites (the fade's rule). Canvas
  /// mode keeps the PAPER static and moves only the merged content, clipped to
  /// the canvas (R7-③: "the canvas stays put, the contents move as one") — the
  /// paper is the panel's stage, not part of the cut's picture there.
  ///
  /// ⚠️NO CALLER passes this today. It was the V row's `Track.transformTrack`,
  /// torn down in the O.L round: a whole track's output posed on the stage only
  /// means something when several tracks stack, and there is no V-track
  /// authoring. The slot stays because it is the shared renderer's capability
  /// and a row that should own a transform declares that through
  /// [timelineRowOwnsTransform] — but nothing declares it, so treat this as
  /// unexercised until something does.
  final TransformPose? cutPose;

  /// The cut pose's anchor; null = the display-space center. Unexercised for
  /// the same reason as [cutPose].
  final CanvasPoint? cutAnchorPoint;

  /// The V track's EFFECT chain, already sampled at this frame
  /// ([trackEffectPaintAt]) — a layer's fx one level up, filtering the cut's
  /// finished PICTURE. It lands on the composite draw for the same reason
  /// [imageOpacity] does: the paper is the panel's stage, not part of the
  /// cut's picture, so a grade on the V row must not tint the stage. None
  /// costs nothing.
  final CompositeEffectPaint cutEffects;

  /// The fade (the track's opacity lane): the cut's WHOLE contribution —
  /// stage and picture together — thins as one (R3b, "fade is
  /// transparency"): what a fade reveals is whatever lies BEHIND the cut
  /// (the tracks below, then the backdrop), never a painted-on wash. The
  /// old per-cut FO/WO target color is gone with the wash; a white-out is
  /// a white cut on a lower track now. 1 costs nothing (no saveLayer).
  final double fadeOpacity;

  /// Alpha on the composite draw itself. The stacked views fade a
  /// NON-bottom track through this instead of [fadeOpacity]: the bottom
  /// track's fade takes its stage along, but a track above the stage
  /// fading away should reveal it. 1 costs nothing.
  final double imageOpacity;

  final Color letterboxColor;
  final Color paperColor;

  /// The project PAPER (R10-⑥); when set it wins over [paperColor] —
  /// alpha included (R3b): a thinned paper reveals the pasteboard and the
  /// backdrop behind it.
  final ProjectBackground? paperBackground;

  /// The PASTEBOARD fill behind the paper (R3b, camera mode only): the
  /// bottom covered track's stage fills its whole output frame with this
  /// before the paper lands — the cut unit the fade thins is
  /// pasteboard + paper + picture. Null = no stage fill (upper tracks,
  /// canvas mode where the panel supplies its own surroundings).
  final Color? pasteboardColor;

  /// False = no paper at all (playlist GAPS, UI-R9 #2): the panel's own
  /// background shows through — the same void the gap-parked scrub
  /// preview shows. There is no cut in a gap, so there is no paper.
  final bool paintPaper;

  /// False = camera mode fills nothing outside the frame (stays
  /// transparent). The multitrack stack paints one frame per track: only
  /// the bottom one letterboxes, the ones above composite over it.
  final bool paintLetterbox;

  /// The view's DPR, for [applyViewportTransform]'s pan-phase snap. The
  /// canvas panel wires it so playback frames land on the SAME device
  /// grid the editing stack snaps to — entering/leaving playback must not
  /// hop the picture by a sub-pixel. Export passes no [viewport], so the
  /// default never reaches pixels there.
  final double devicePixelRatio;

  /// The SE rows' on-canvas NAME TAGS at this frame (R5b, §6-z15), drawn
  /// in canvas space directly over the composite — never baked into it
  /// (the camera's rule): the text comes from the SE frames themselves,
  /// so a rename shows instantly without invalidating one cached
  /// composite. They ride the camera projection and the cut pose exactly
  /// like the artwork they annotate.
  final List<ResolvedSeNameTag> seNameTags;

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
      applyViewportTransform(
        canvas,
        resolvedViewport,
        devicePixelRatio: devicePixelRatio,
      );
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

    // The FADE is transparency now (R3b): the cut's whole contribution —
    // stage fill, paper, picture — thins as one layer, revealing whatever
    // lies behind (the tracks below, then the backdrop). Only a mid-fade
    // frame pays the saveLayer.
    final fading = fadeOpacity < 1;
    if (fading) {
      canvas.saveLayer(
        frameRect ?? canvasRect,
        Paint()..color = Color.fromRGBO(0, 0, 0, fadeOpacity.clamp(0.0, 1.0)),
      );
    }
    if (pose != null && pasteboardColor != null) {
      // The stage's apron: the camera sees the pasteboard wherever it
      // reaches past the paper — part of the cut unit, so it fades with
      // it.
      canvas.drawRect(frameRect!, Paint()..color = pasteboardColor!);
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
      // 🚨SCRUB ↔ STILL PARITY (device report B2, 2026-08-17): in canvas
      // mode with a canvas-resolution composite this draw IS the editing
      // canvas's one resample — the same canvas-space pixels, under the
      // same snapped viewport transform, standing in for the editing
      // stack's buffer blit during a scrub. It must therefore follow the
      // same T21 display law ([filterQualityForDisplayScale]: magnified
      // and 1:1 sample `none`, reduced filters) — hardcoded `low` here
      // made every axis-aligned edge land bilinear on this route and
      // nearest on the editing one, a whole-picture 1px "반올림" at any
      // fractional device phase (DPR 1.25/1.5 makes even 100% zoom one).
      //
      // The law's premise is a canvas-resolution image (displayScaleOf's
      // contract: "the buffer is at canvas resolution"). A Half/Quarter
      // cache upscales to canvas size inside this same draw, and that
      // upscale keeps its bilinear sampling — today's value for the
      // degraded tiers, which can never be byte-equal to the editing
      // canvas anyway. Camera mode (and the unexercised cut pose) project
      // through transforms the editing canvas never renders, so they too
      // keep the sampling they always had.
      final editingResample =
          pose == null &&
          resolvedCutPose == null &&
          composite.width == canvasSize.width &&
          composite.height == canvasSize.height;
      final imagePaint = Paint()
        ..filterQuality = editingResample
            ? filterQualityForDisplayScale(
                displayScaleOf(resolvedViewport?.zoom ?? 1),
              )
            : FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, imageOpacity.clamp(0.0, 1.0));
      // The V row's chain filters the picture on its way onto the stage.
      cutEffects.applyTo(imagePaint);
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
        imagePaint,
      );
    }
    if (seNameTags.isNotEmpty) {
      // The tags belong to the cut's own contribution, so a stacked UPPER
      // track thins them with its picture: that track fades through
      // [imageOpacity] (only the bottom track's [fadeOpacity] saveLayer
      // above carries the tags for free), and an annotation left fully
      // opaque over a fading picture reads as a bug.
      final thinning = imageOpacity < 1;
      if (thinning) {
        canvas.saveLayer(
          frameRect ?? canvasRect,
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, imageOpacity.clamp(0.0, 1.0)),
        );
      }
      paintSeNameTags(canvas, tags: seNameTags, canvasSize: canvasSize);
      if (thinning) {
        canvas.restore();
      }
    }
    if (pose != null) {
      canvas.restore();
    }
    if (resolvedCutPose != null) {
      canvas.restore();
    }
    if (fading) {
      canvas.restore();
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
      oldDelegate.cutEffects != cutEffects ||
      oldDelegate.fadeOpacity != fadeOpacity ||
      oldDelegate.imageOpacity != imageOpacity ||
      oldDelegate.letterboxColor != letterboxColor ||
      oldDelegate.paperColor != paperColor ||
      oldDelegate.paperBackground != paperBackground ||
      oldDelegate.pasteboardColor != pasteboardColor ||
      oldDelegate.paintPaper != paintPaper ||
      oldDelegate.paintLetterbox != paintLetterbox ||
      // The pan-phase snap reads it — a monitor move must repaint, not
      // keep the old phase.
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      seNameTagSignature(oldDelegate.seNameTags) !=
          seNameTagSignature(seNameTags);
}
