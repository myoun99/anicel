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

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/draw_space.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/transform_track.dart';
import '../../services/composite_effect_paint.dart';
import 'subtree_image_composite.dart';
import '../../services/layer_pose_paint.dart';

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
/// [texelScale] is how many target pixels one canvas unit is on [canvas]
/// when [canvas] is a pixel raster whose grid is aligned to canvas space —
/// the display buffer, a sub-tree raster, the playback composite — and null
/// when it is not (the screen, a projection). It is what tells a texel copy
/// from a resample ([_isTexelCopy]). ⛔REQUIRED, the A4 way: a route that
/// inherited a guess would draw a resample unfiltered.
///
/// A4 — [filterQuality] is REQUIRED, deliberately. A default here is how
/// the sampling drift this file exists to end comes back: a new route
/// "just draws" and inherits a quality nobody chose. Requiring the
/// argument blocks the CLASS, not the instance — every route answers the
/// sampling question at its call site, in writing, and the source
/// contract test (`layer_image_draw_contract_test.dart`) freezes the
/// raw-draw census so new image draws have to come through here. It is the
/// answer for a draw that RESAMPLES; a texel copy resamples nothing and is
/// drawn at `none` whatever the route asked.
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
  required double? texelScale,
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
        ..color = alphaOnly(opacity)
        // R26 #30: the layer blend applies at composite time, so every
        // route shows the picture playback composes.
        ..blendMode = blendMode.paintBlendMode;
      // Onion-skin Colors mode: the ghost converts fully to the tint —
      // every drawn pixel takes the tint's RGB and only alpha survives.
      //
      // ★IT GOES THROUGH THE RESOLVER NOW, not onto the paint here. Written
      // straight to `Paint.colorFilter` it OWNED that slot, so a ghost could
      // wear the tint or the row's chain and never both — which is why
      // ghosts used to carry no effects at all. Folded into the resolver's
      // matrix it composes with the colour effects, and 유저 2026-08-27
      // (I-8-Q5) asked for exactly that: the ghost shows what the screen
      // shows.
      // 🚨A CHAIN IS NOT ALWAYS ONE DRAW. A colour key is a fragment shader,
      // so a key that comes after painted state needs its own raster — the
      // same steps a group takes, asked of one layer's image.
      final plan = resolveCompositeEffectPlan(
        effects,
        // The pose above already scaled this canvas, so there is no CTM left
        // for Skia to map the sigma through — the chain arrives multiplied.
        space: rasterScale == 1
            ? DrawSpace.canvas
            : DrawSpace.preScaled(rasterScale),
        tint: tint,
      );
      plan.finalPaint.applyTo(paint);
      // ⛔THE STEP SCALE IS NOT `rasterScale`, even though it equals it here.
      // `rasterScale` answers "what space does the DRAW land in"; the steps
      // ask "how many image pixels is a canvas pixel". On this route the
      // image is at the same raster the canvas is, so the two numbers agree
      // — which is exactly why one parameter was answering both until the
      // playback painter needed them to differ. Derived, so it cannot drift.
      final stepped = steppedForChain(
        image: image,
        plan: plan,
        canvasExtent: worldRect.width,
      );
      // 🚨★★★A TEXEL COPY RESAMPLES NOTHING, SO IT IS DRAWN AT `none` (유저
      // 2026-09-24 「통일해서」). The law the 1:1 blits beside it already keep
      // — the sub-tree blit, the tile blits, the buffer carry — asked of a
      // layer image: below 100% the buffer and the playback composite lay
      // each level image down one texel per pixel, and filtering that is
      // only a copy on paper. 🔬Measured against the source image: bilinear
      // at 1:1 IS the copy on the Windows app (Impeller GLES) and the test
      // runner, and is NOT on Impeller Vulkan — Android's default — up to
      // 9/255 off at a 2340×1654 image and 4/255 at the fit-zoom level,
      // growing with the size. `none` is the copy on all three. So a layer
      // drawn this way was a hair softer on Android than the same layer
      // being drawn on, whose tiles are `none` — the active/inactive split
      // D14 ruled out (「그림 자체에 통일해서 적용」).
      final copies =
          pose == null && _isTexelCopy(stepped, worldRect, texelScale);
      assert(() {
        if (copies) {
          debugTexelCopies += 1;
        }
        return true;
      }());
      paint.filterQuality = copies ? ui.FilterQuality.none : filterQuality;
      try {
        if (drawAtOrigin) {
          canvas.drawImage(stepped, ui.Offset.zero, paint);
          return;
        }
        canvas.drawImageRect(
          stepped,
          ui.Rect.fromLTWH(
            0,
            0,
            stepped.width.toDouble(),
            stepped.height.toDouble(),
          ),
          ui.Rect.fromLTWH(
            worldRect.left * rasterScale,
            worldRect.top * rasterScale,
            worldRect.width * rasterScale,
            worldRect.height * rasterScale,
          ),
          paint,
        );
      } finally {
        // ⛔The steps made a NEW image; the one handed in belongs to the
        // cache. Disposing that would take the layer's pixels with it.
        if (!identical(stepped, image)) {
          stepped.dispose();
        }
      }
    },
  );
}

/// Whether [image] drawn into [worldRect] lands texel for texel on a canvas
/// whose pixels are [texelScale] canvas units apart: one texel per target
/// pixel, starting on a whole pixel.
bool _isTexelCopy(ui.Image image, ui.Rect worldRect, double? texelScale) {
  if (texelScale == null) {
    return false;
  }
  bool whole(double value) => value == value.roundToDouble();
  return image.width == worldRect.width * texelScale &&
      image.height == worldRect.height * texelScale &&
      whole(worldRect.left * texelScale) &&
      whole(worldRect.top * texelScale);
}

/// How many layer draws were texel copies — so a pin can say WHICH routes
/// copy: the test runner draws a bilinear 1:1 exactly as it draws a copy, so
/// the pixels cannot tell whether a route declared its raster. Written
/// under `assert`.
@visibleForTesting
int debugTexelCopies = 0;
