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
  /// [paint] must arrive with NO `colorFilter` of its own. It once arrived
  /// carrying the onion tint, and that is exactly what this class now takes
  /// over ([resolveCompositeEffectPaint]'s `tint`) — the slot holds one
  /// filter, so anything writing it beforehand silently decided the ghost
  /// could not also wear its row's chain. The assert makes a second writer
  /// a test failure rather than a look nobody can explain.
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

  // A VALUE, so a painter can ask "is this the same filter as last frame?"
  // in `shouldRepaint` — the V row's cut chain is resolved fresh every build,
  // and identity would call a static grade a change on every rebuild.
  // dart:ui's filters carry value equality themselves.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompositeEffectPaint &&
          other.colorFilter == colorFilter &&
          other.imageFilter == imageFilter &&
          other.outsetPixels == outsetPixels;

  @override
  int get hashCode => Object.hash(colorFilter, imageFilter, outsetPixels);
}

/// The single folded matrix for a COLOUR-ONLY chain; null as soon as the
/// chain contains anything spatial (a blur), because a matrix cannot say
/// what a blur does.
///
/// STRICT on purpose: a caller that gets a matrix may paint it INSTEAD of
/// the chain, so answering "here is the colour part" for a chain with a
/// blur in it would silently drop the blur. The adjustment scope relies on
/// that to fold its MIX into the matrix ([lerpColorMatrixFromIdentity])
/// and paint one pass. Readers that only want the colour part and know
/// they cannot do spatial work at all — the eyedropper — ask
/// [resolveColorMatrixIgnoringSpatial] instead.
List<double>? resolveColorOnlyMatrix(List<ResolvedLayerEffect> effects) {
  for (final effect in effects) {
    if (effect.kind.spreadsPixels) {
      return null;
    }
  }
  return resolveColorMatrixIgnoringSpatial(effects);
}

/// The folded matrix of the chain's COLOUR effects, with the spatial ones
/// (a blur) skipped; null when there are no colour effects at all.
///
/// Only for readers that cannot do spatial work under any circumstances —
/// the eyedropper answers "what colour is at this point" from one pixel, so
/// a blur is out of reach either way and dropping the colour grade with it
/// would be strictly worse. Never use this to PAINT: see
/// [resolveColorOnlyMatrix].
List<double>? resolveColorMatrixIgnoringSpatial(
  List<ResolvedLayerEffect> effects,
) {
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
      // A color key changes ALPHA by a threshold test — there is no color
      // matrix for it, the same way there is none for a blur. The reader
      // this serves samples one pixel, so it applies the keys itself
      // (`CelColorKey.alphaFor`) rather than asking for a matrix that
      // cannot exist.
      EffectKind.deleteColor || EffectKind.keepColor => null,
    };
    if (next == null) {
      continue;
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
/// The onion-skin Colors tint as a color matrix: every pixel takes the
/// tint's RGB and keeps only its own alpha (scaled by the tint's).
///
/// 🚨THIS EXISTS SO THE GHOST CAN HAVE BOTH. The tint used to be written
/// straight onto `Paint.colorFilter`, which is ONE slot — so a ghost could
/// wear the tint or the row's effects, never both, and the chain was
/// dropped with a comment calling ghosts "editing scaffolding". That was
/// the slot talking, not a decision. ✅유저 2026-08-27 (I-8-Q5) chose "the
/// ghost shows the pixels the screen shows", and a matrix composes with the
/// color effects for free — only a blur still needs its own buffer.
///
/// Rows are `ColorFilter.mode(tint, srcIn)` written out: out.rgb = tint.rgb,
/// out.a = tint.a × in.a. The translation column is 0…255, per
/// `ColorFilter.matrix`'s contract.
List<double> onionTintColorMatrix(int argb) {
  final alpha = ((argb >> 24) & 0xFF) / 255.0;
  final red = ((argb >> 16) & 0xFF).toDouble();
  final green = ((argb >> 8) & 0xFF).toDouble();
  final blue = (argb & 0xFF).toDouble();
  return <double>[
    0, 0, 0, 0, red, //
    0, 0, 0, 0, green,
    0, 0, 0, 0, blue,
    0, 0, 0, alpha, 0,
  ];
}

CompositeEffectPaint resolveCompositeEffectPaint(
  List<ResolvedLayerEffect> effects, {
  double rasterScale = 1,
  int? tint,
}) {
  if (effects.isEmpty && tint == null) {
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
      // ⛔THE CPU HALF MUST BE GONE BY NOW. `splitSourceEffects` takes the
      // color keys out in the shared visit and `celSurfaceWithSourceEffects`
      // has already applied them to the surface this paint will draw.
      // Reaching here means a route resolved a chain without splitting it —
      // an assert rather than a silent skip, because the silent version
      // looks exactly like "the artist set Amount to 0".
      case EffectKind.deleteColor:
      case EffectKind.keepColor:
        assert(
          false,
          'Source-pixel effects must be split off before a paint is '
          'resolved — see splitSourceEffects.',
        );
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

  if (tint != null) {
    // LAST, over the finished pixel: the ghost is a picture of the row as
    // the screen shows it, converted to the peg's colour.
    final tintMatrix = onionTintColorMatrix(tint);
    pendingColor = pendingColor == null
        ? tintMatrix
        : composeColorMatrices(tintMatrix, pendingColor!);
  }

  if (chain == null) {
    // Null when the chain held nothing this function paints — a release
    // build reaching the assert above lands here, and "no paint state" is
    // the honest answer for it.
    final matrix = pendingColor;
    if (matrix == null || colorMatrixIsIdentity(matrix)) {
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

  /// The buffer bounds for every pass.
  final ui.Rect bufferBounds;

  /// The filtered pass's paint. Non-null always.
  final ui.Paint filteredPaint;

  /// Non-null ONLY when the scope must crossfade (a blur below full mix):
  /// the outer buffer the two passes add up inside.
  final ui.Paint? crossfadeLayerPaint;

  /// The unfiltered pass's paint; non-null exactly when
  /// [crossfadeLayerPaint] is.
  final ui.Paint? unfilteredPaint;

  /// Whether the route has to draw the scope a second time.
  bool get crossfades => crossfadeLayerPaint != null;
}

/// Resolves the pass for an adjustment scope of [effects] at [mix] over
/// [bounds]. [rasterScale] follows the same rule as
/// [resolveCompositeEffectPaint].
///
/// A route runs it as ONE raster and one or two blits. The scope is the same
/// picture in both passes, so it is rasterised once — on the playback route
/// "drawing the scope" means awaiting every layer image in it, and the second
/// pass was not a rounding error:
/// ```dart
/// drawSubtreeAsImage(
///   canvas: canvas,
///   bounds: pass.bufferBounds,
///   rasterScale: rasterScale,
///   maxPixelSide: maxSubtreeRasterSide,
///   paintSubtree: drawScope,
///   compose: (blit) {
///     if (pass.crossfades) {
///       // An alpha group over two draws of one image — not a buffer
///       // anything needs to sample, so it stays a layer.
///       canvas.saveLayer(pass.bufferBounds, pass.crossfadeLayerPaint!);
///       blit(pass.unfilteredPaint!);
///     }
///     blit(pass.filteredPaint);
///     if (pass.crossfades) canvas.restore();
///   },
/// );
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
