import 'dart:ui' as ui;

import '../../core/color_matrix.dart';
import '../../models/layer_effect.dart';

/// How much a blur RADIUS parameter spreads, as a Gaussian sigma. A radius
/// is the visible reach of the blur; three sigma covers it, so a radius of
/// 3 canvas px reads as sigma 1 — the convention Photoshop's radius slider
/// follows closely enough that a number typed from muscle memory lands
/// where the artist expects.
const double blurSigmaPerRadius = 1 / 3;

/// How far past its own coverage a blur of [radius] paints. Used to outset
/// `saveLayer` bounds so a group's blur is not clipped at the buffer edge.
double blurSpreadForRadius(double radius) => radius;

/// The Skia form of a resolved effect chain — ONE pure translation from
/// effect samples to paint state, shared by every composite route (editing
/// stack, playback cache, camera renders, export). The R5b lesson applied:
/// one resolver, one painter, no surface deciding for itself what a blur
/// means.
///
/// The chain lands in exactly one of the two fields:
/// - **colorFilter** while the chain is colors only. Color filters run
///   INLINE, with no offscreen, so the overwhelmingly common case
///   ("brighten this layer") costs a matrix multiply per pixel and nothing
///   else. Several colour effects fold into one matrix
///   ([composeColorMatrices]).
/// - **imageFilter** as soon as a blur appears — a blur needs an offscreen
///   anyway, so the colours ride along inside the composed filter (setting
///   both fields would leave Skia's application order deciding the look).
class CompositeEffectPaint {
  const CompositeEffectPaint({
    this.colorFilter,
    this.imageFilter,
    this.outsetPixels = 0,
  });

  static const CompositeEffectPaint none = CompositeEffectPaint();

  final ui.ColorFilter? colorFilter;
  final ui.ImageFilter? imageFilter;

  /// How far the chain paints beyond its input's bounds (blur spread, in
  /// the same space the plan was resolved for).
  final double outsetPixels;

  bool get isEmpty => colorFilter == null && imageFilter == null;
  bool get isNotEmpty => !isEmpty;

  /// Writes the plan onto [paint] — the ONLY way a route should apply
  /// effects.
  ///
  /// [paint]'s existing `colorFilter` (the onion-skin tint) is never
  /// overwritten: onion ghosts are editing scaffolding and deliberately
  /// carry no effects, so the two can never both be set. The assert makes
  /// that a test failure rather than a look nobody can explain.
  void applyTo(ui.Paint paint) {
    if (isEmpty) {
      return;
    }
    assert(
      paint.colorFilter == null,
      'A paint already carrying a colorFilter (the onion tint) must not '
      'also take effects — ghosts resolve to CompositeEffectPaint.none.',
    );
    if (colorFilter != null) {
      paint.colorFilter = colorFilter;
      return;
    }
    paint.imageFilter = imageFilter;
  }
}

/// Translates [effects] (already sampled at a frame) into paint state.
///
/// [rasterScale] is the ratio between the space this paint draws in and
/// CANVAS space. Colour is scale-free, but a blur radius is measured in
/// canvas pixels: the playback cache composes at a reduced raster and draws
/// its pre-scaled images 1:1, so without this a half-size preview would
/// show a double-strength blur. Routes that draw under a scaled CANVAS
/// TRANSFORM (the editing stack, the camera projection) leave it 1 — Skia
/// maps the sigma through the CTM for them.
CompositeEffectPaint resolveCompositeEffectPaint(
  List<ResolvedLayerEffect> effects, {
  double rasterScale = 1,
}) {
  if (effects.isEmpty) {
    return CompositeEffectPaint.none;
  }

  // Colour matrices accumulate until a blur forces an offscreen; then the
  // pending matrix becomes the innermost node of the image-filter chain.
  List<double>? pendingColor;
  ui.ImageFilter? chain;
  var outset = 0.0;

  void flushPendingColor() {
    if (pendingColor == null) {
      return;
    }
    final filter = ui.ColorFilter.matrix(pendingColor!);
    chain = chain == null
        ? filter
        : ui.ImageFilter.compose(outer: filter, inner: chain!);
    pendingColor = null;
  }

  for (final effect in effects) {
    switch (effect.kind) {
      case EffectKind.brightnessContrast:
        final matrix = brightnessContrastMatrix(
          brightness: effect.parameter('brightness'),
          contrast: effect.parameter('contrast'),
        );
        pendingColor = pendingColor == null
            ? matrix
            : composeColorMatrices(matrix, pendingColor!);
      case EffectKind.hueSaturation:
        final matrix = hueSaturationMatrix(
          hueDegrees: effect.parameter('hue'),
          saturation: effect.parameter('saturation'),
          lightness: effect.parameter('lightness'),
        );
        pendingColor = pendingColor == null
            ? matrix
            : composeColorMatrices(matrix, pendingColor!);
      case EffectKind.blur:
        flushPendingColor();
        final radiusX = effect.parameter('blurX') * rasterScale;
        final radiusY = effect.parameter('blurY') * rasterScale;
        final blur = ui.ImageFilter.blur(
          sigmaX: radiusX * blurSigmaPerRadius,
          sigmaY: radiusY * blurSigmaPerRadius,
          // DECAL, not the clamp default: a layer's artwork must not smear
          // its edge pixels outward forever — outside its coverage there is
          // nothing, and that is what the picture should show.
          tileMode: ui.TileMode.decal,
        );
        chain = chain == null
            ? blur
            : ui.ImageFilter.compose(outer: blur, inner: chain!);
        outset += blurSpreadForRadius(radiusX > radiusY ? radiusX : radiusY);
    }
  }

  if (chain == null) {
    final matrix = pendingColor!;
    if (colorMatrixIsIdentity(matrix)) {
      return CompositeEffectPaint.none;
    }
    return CompositeEffectPaint(colorFilter: ui.ColorFilter.matrix(matrix));
  }
  flushPendingColor();
  return CompositeEffectPaint(imageFilter: chain, outsetPixels: outset);
}

/// The `saveLayer` bounds for a buffered group whose chain is [plan]:
/// [bounds] grown by the blur spread, so a group blur is not clipped at the
/// buffer edge it was meant to bleed past.
ui.Rect effectBufferBounds(ui.Rect bounds, CompositeEffectPaint plan) {
  if (plan.outsetPixels <= 0) {
    return bounds;
  }
  return bounds.inflate(plan.outsetPixels);
}

/// How a route paints an ADJUSTMENT scope (R6b) — the semantics in ONE
/// place, so the four composite routes only have to run the steps.
///
/// The row's opacity is a MIX, not a fade. `saveLayer(alpha)` around the
/// filtered scope would thin the whole stack toward transparent, which is
/// a shocking thing for an opacity slider to do to a grade; Photoshop
/// crossfades between the unfiltered and the filtered picture instead. So
/// below full strength the scope is drawn TWICE: once as it is, then the
/// filtered copy over it at [AdjustmentScopePass.filteredPaint]'s alpha.
/// At full strength — the overwhelmingly common case — it is drawn once.
class AdjustmentScopePass {
  const AdjustmentScopePass({
    required this.drawsUnfilteredFirst,
    required this.bufferBounds,
    required this.filteredPaint,
  });

  /// Whether the route must draw the scope once unfiltered before opening
  /// the buffer (the crossfade's bottom half).
  final bool drawsUnfilteredFirst;

  /// The `saveLayer` bounds for the filtered pass.
  final ui.Rect bufferBounds;

  /// The `saveLayer` paint: the chain's filter, plus the mix as alpha when
  /// the scope crossfades.
  final ui.Paint filteredPaint;
}

/// Resolves the pass for an adjustment scope of [effects] at [mix] over
/// [bounds]. [rasterScale] follows the same rule as
/// [resolveCompositeEffectPaint].
AdjustmentScopePass resolveAdjustmentScopePass({
  required ui.Rect bounds,
  required List<ResolvedLayerEffect> effects,
  required double mix,
  double rasterScale = 1,
}) {
  final plan = resolveCompositeEffectPaint(effects, rasterScale: rasterScale);
  final crossfades = mix < 1;
  final paint = ui.Paint();
  if (crossfades) {
    paint.color = ui.Color.fromRGBO(0, 0, 0, mix.clamp(0.0, 1.0));
  }
  plan.applyTo(paint);
  return AdjustmentScopePass(
    drawsUnfilteredFirst: crossfades,
    bufferBounds: effectBufferBounds(bounds, plan),
    filteredPaint: paint,
  );
}
