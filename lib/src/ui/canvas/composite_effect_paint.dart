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

/// The single folded matrix for a COLOUR-ONLY chain; null as soon as the
/// chain contains anything spatial (a blur), because a matrix cannot say
/// what a blur does.
///
/// Exposed so the adjustment scope can fold its MIX into the same matrix
/// ([lerpColorMatrixFromIdentity]) instead of crossfading two draws.
List<double>? resolveColorOnlyMatrix(List<ResolvedLayerEffect> effects) {
  List<double>? matrix;
  for (final effect in effects) {
    final next = switch (effect.kind) {
      EffectKind.brightnessContrast => brightnessContrastMatrix(
        brightness: effect.parameter('brightness'),
        contrast: effect.parameter('contrast'),
      ),
      EffectKind.hueSaturation => hueSaturationMatrix(
        hueDegrees: effect.parameter('hue'),
        saturation: effect.parameter('saturation'),
        lightness: effect.parameter('lightness'),
      ),
      EffectKind.blur => null,
    };
    if (next == null) {
      return null;
    }
    matrix = matrix == null ? next : composeColorMatrices(next, matrix);
  }
  return matrix;
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
/// The row's opacity is a MIX, not a fade: half strength means half a
/// grade, never a half-transparent stack. Getting that right is the whole
/// content of this class, and the naive spelling is wrong twice over:
///
/// - `saveLayer(alpha)` around the filtered scope thins the picture toward
///   transparent — the shocking answer;
/// - drawing the scope unfiltered and then the filtered copy over it with
///   src-over gives `m·F + (1 − m·aF)·U`, which is `lerp(U, F, m)` only
///   where the scope is fully OPAQUE. On a translucent picture it COMPOUNDS
///   alpha (a 50 % layer under a 50 % mix came out at 62.5 %).
///
/// So a colour-only chain folds the mix into its own matrix
/// ([lerpColorMatrixFromIdentity]) and paints in ONE pass — exact, and no
/// second draw of the scope at all. Only a chain with a BLUR needs the two
/// passes, and those are done inside one crossfade buffer with the second
/// pass ADDED (`BlendMode.plus`) onto a `1 − mix` first pass, which is a
/// true lerp with alpha left alone.
class AdjustmentScopePass {
  const AdjustmentScopePass({
    required this.bufferBounds,
    required this.filteredPaint,
    this.crossfadeLayerPaint,
    this.unfilteredPaint,
  });

  /// The `saveLayer` bounds for every pass.
  final ui.Rect bufferBounds;

  /// The filtered pass's `saveLayer` paint. Non-null always.
  final ui.Paint filteredPaint;

  /// Non-null ONLY when the scope must crossfade (a blur below full mix):
  /// the outer buffer the two passes add up inside.
  final ui.Paint? crossfadeLayerPaint;

  /// The unfiltered pass's `saveLayer` paint; non-null exactly when
  /// [crossfadeLayerPaint] is.
  final ui.Paint? unfilteredPaint;

  /// Whether the route has to draw the scope a second time.
  bool get crossfades => crossfadeLayerPaint != null;
}

/// Resolves the pass for an adjustment scope of [effects] at [mix] over
/// [bounds]. [rasterScale] follows the same rule as
/// [resolveCompositeEffectPaint].
///
/// A route runs it as:
/// ```dart
/// if (pass.crossfades) {
///   canvas.saveLayer(pass.bufferBounds, pass.crossfadeLayerPaint!);
///   canvas.saveLayer(pass.bufferBounds, pass.unfilteredPaint!);
///   drawScope();
///   canvas.restore();
/// }
/// canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
/// drawScope();
/// canvas.restore();
/// if (pass.crossfades) canvas.restore();
/// ```
AdjustmentScopePass resolveAdjustmentScopePass({
  required ui.Rect bounds,
  required List<ResolvedLayerEffect> effects,
  required double mix,
  double rasterScale = 1,
}) {
  final strength = mix.clamp(0.0, 1.0);
  if (strength < 1) {
    final colorMatrix = resolveColorOnlyMatrix(effects);
    if (colorMatrix != null) {
      // The exact answer in one pass: the mix IS part of the matrix.
      return AdjustmentScopePass(
        bufferBounds: bounds,
        filteredPaint: ui.Paint()
          ..colorFilter = ui.ColorFilter.matrix(
            lerpColorMatrixFromIdentity(colorMatrix, strength),
          ),
      );
    }
  }
  final plan = resolveCompositeEffectPaint(effects, rasterScale: rasterScale);
  final bufferBounds = effectBufferBounds(bounds, plan);
  if (strength >= 1) {
    final paint = ui.Paint();
    plan.applyTo(paint);
    return AdjustmentScopePass(
      bufferBounds: bufferBounds,
      filteredPaint: paint,
    );
  }
  // A spatial chain below full strength: two passes ADDED inside one
  // buffer. `plus` on premultiplied colour gives (1−m)·U + m·F exactly,
  // and the two alphas sum back to the scope's own.
  final filtered = ui.Paint()
    ..color = ui.Color.fromRGBO(0, 0, 0, strength)
    ..blendMode = ui.BlendMode.plus;
  plan.applyTo(filtered);
  return AdjustmentScopePass(
    bufferBounds: bufferBounds,
    filteredPaint: filtered,
    crossfadeLayerPaint: ui.Paint(),
    unfilteredPaint: ui.Paint()
      ..color = ui.Color.fromRGBO(0, 0, 0, 1 - strength),
  );
}
