/// How a POSED LAYER IMAGE reaches a canvas — the one place that decides
/// it (P2a).
///
/// Four routes composite the same thing (playback's cache, the camera
/// render, the editing stack, and export) and each hand-rolled the same
/// four steps: save, apply the pose, build a paint out of opacity, blend
/// mode and the effect chain, draw, restore. They agreed on the shape and
/// disagreed in the details — most visibly on sampling quality, where the
/// editing stack drew the ACTIVE layer's tiles unfiltered and everything
/// else at `FilterQuality.low`, so zooming in made the layer you were
/// drawing on the only jagged one on screen.
///
/// This converges the DRAW. It deliberately does not converge the INPUTS,
/// where the same four routes also disagree — which canvas size owns the
/// pose, whether pasteboard artwork is cropped first — because those
/// change rendered bytes and belong in their own change.
///
/// It is for LAYER images only. The same `applyLayerPoseTransform` also
/// carries the cut pose and the V-track pose, but those apply to an
/// already-composed frame in output space and must not quietly inherit a
/// layer-level sampling policy.
library;

import 'dart:ui' as ui;

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/transform_track.dart';
import 'composite_effect_paint.dart';
import 'layer_pose_paint.dart';

/// Runs [body] under [pose].
///
/// Separate from [drawPosedLayerImage] because the editing stack's pose
/// wrap straddles a node that HAS a pose and has no image: the live
/// surface is painted tile by tile by its own painter, and it still has to
/// sit under the same transform as everything else in the stack.
///
/// A null pose runs [body] with no save/restore at all, which is what all
/// three call sites already did — an identity layer should not pay for a
/// matrix, and more importantly the balance is easier to see this way than
/// as a save whose restore is fifty lines below.
T withLayerPose<T>(
  ui.Canvas canvas, {
  required TransformPose? pose,
  required CanvasSize canvasSize,
  CanvasPoint? anchorPoint,
  double rasterScale = 1,
  required T Function() body,
}) {
  if (pose == null) {
    return body();
  }
  canvas.save();
  try {
    applyLayerPoseTransform(
      canvas,
      pose,
      canvasSize,
      anchorPoint: anchorPoint,
      rasterScale: rasterScale,
    );
    return body();
  } finally {
    canvas.restore();
  }
}

/// One layer's image, posed, faded, blended, filtered and drawn.
///
/// [worldRect] is where the image belongs in canvas space: the canvas rect
/// for an ordinary cel, grown for pasteboard content. [rasterScale] is the
/// quality tier the destination canvas is rastering at — it scales the
/// destination rect AND reaches the effect resolver, because the images
/// are already at that tier and a canvas-pixel blur radius that ignored it
/// would show at double strength in a half-size preview.
///
/// [drawAtOrigin] takes the legacy `drawImage(Offset.zero)` path instead
/// of `drawImageRect`. It is a byte pin rather than an optimisation: two
/// of the routes have always drawn their canvas-extent images that way and
/// their output is held to the pixel by composite parity suites, so
/// switching them to the general path is a change of rendered bytes and
/// does not belong in a convergence.
///
/// A4 — [filterQuality] is REQUIRED, deliberately. A default here is how
/// the sampling drift this file exists to end comes back: a new route
/// "just draws" and inherits a quality nobody chose. Requiring the
/// argument blocks the CLASS, not the instance — every route answers the
/// sampling question at its call site, in writing, and the source
/// contract test (`layer_image_draw_contract_test.dart`) freezes the
/// raw-draw census so new image draws have to come through here.
void drawPosedLayerImage(
  ui.Canvas canvas, {
  required ui.Image image,
  required ui.Rect worldRect,
  required CanvasSize canvasSize,
  required TransformPose? pose,
  CanvasPoint? anchorPoint,
  required double opacity,
  required LayerBlendMode blendMode,
  List<ResolvedLayerEffect> effects = const <ResolvedLayerEffect>[],
  double rasterScale = 1,
  required ui.FilterQuality filterQuality,
  int? tint,
  bool drawAtOrigin = false,
}) {
  withLayerPose(
    canvas,
    pose: pose,
    canvasSize: canvasSize,
    anchorPoint: anchorPoint,
    rasterScale: rasterScale,
    body: () {
      final paint = ui.Paint()
        ..filterQuality = filterQuality
        ..color = ui.Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))
        // R26 #30: the layer blend applies at composite time, so every
        // route shows the picture playback composes.
        ..blendMode = blendMode.paintBlendMode;
      // Onion-skin Colors mode: the ghost converts fully to the tint —
      // every drawn pixel takes the tint's RGB and only alpha survives.
      //
      // This MUST come before the effect chain. `applyTo` asserts the
      // paint carries no colorFilter yet, because the two would fight for
      // the same slot; ghosts resolve to no effects at all, so the assert
      // is a guard on that invariant rather than an ordering accident.
      if (tint != null) {
        paint.colorFilter = ui.ColorFilter.mode(
          ui.Color(tint),
          ui.BlendMode.srcIn,
        );
      }
      resolveCompositeEffectPaint(
        effects,
        rasterScale: rasterScale,
      ).applyTo(paint);
      if (drawAtOrigin) {
        canvas.drawImage(image, ui.Offset.zero, paint);
        return;
      }
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(
          worldRect.left * rasterScale,
          worldRect.top * rasterScale,
          worldRect.width * rasterScale,
          worldRect.height * rasterScale,
        ),
        paint,
      );
    },
  );
}
