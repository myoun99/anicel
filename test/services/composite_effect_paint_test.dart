import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/draw_space.dart';
import 'package:anicel/src/core/color_matrix.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';

/// The ONE translation from resolved effect samples to paint state (R6).
/// Every composite route calls this, so its contract is where the routes
/// agree — or would silently disagree.
void main() {
  ResolvedLayerEffect colour({double brightness = 0, double contrast = 0}) =>
      ResolvedLayerEffect(
        kind: EffectKind.brightnessContrast,
        values: [brightness, contrast],
      );

  ResolvedLayerEffect blur(double blurriness, {int dimensions = 0}) =>
      ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: [blurriness, dimensions.toDouble()],
      );

  test('an empty chain is no paint work at all', () {
    final plan = resolveCompositeEffectPaint(const []);
    expect(plan.isEmpty, isTrue);
    expect(plan.colorFilter, isNull);
    expect(plan.imageFilter, isNull);
    expect(plan.outsetPixels, 0);
  });

  test('a colour-only chain lands on colorFilter — no offscreen', () {
    final plan = resolveCompositeEffectPaint([colour(brightness: 20)]);
    expect(plan.colorFilter, isNotNull);
    expect(plan.imageFilter, isNull);
    expect(
      plan.colorFilter,
      ui.ColorFilter.matrix(
        brightnessContrastMatrix(brightness: 20, contrast: 0),
      ),
      reason: 'the matrix IS the math core — no second implementation here',
    );
  });

  test('two colour effects FOLD into one matrix, still one filter', () {
    final plan = resolveCompositeEffectPaint([
      colour(brightness: 10),
      ResolvedLayerEffect(kind: EffectKind.hueSaturation, values: [0, -100, 0]),
    ]);
    expect(plan.imageFilter, isNull);
    expect(
      plan.colorFilter,
      ui.ColorFilter.matrix(
        composeColorMatrices(
          hueSaturationMatrix(hueDegrees: 0, saturation: -100, lightness: 0),
          brightnessContrastMatrix(brightness: 10, contrast: 0),
        ),
      ),
      reason: 'list order = application order, folded outer∘inner',
    );
  });

  test('a chain that resolves to the identity is dropped', () {
    // Reachable through clamping and through a hue rotation of 360.
    final plan = resolveCompositeEffectPaint([
      ResolvedLayerEffect(kind: EffectKind.hueSaturation, values: [360, 0, 0]),
    ]);
    expect(plan.isEmpty, isTrue);
  });

  test('a blur moves the whole chain onto imageFilter', () {
    final plan = resolveCompositeEffectPaint([
      colour(brightness: 20),
      blur(6, dimensions: 1),
    ]);
    expect(plan.imageFilter, isNotNull);
    expect(
      plan.colorFilter,
      isNull,
      reason: 'setting both would leave Skia deciding the order',
    );
    expect(plan.isNotEmpty, isTrue);
  });

  test('the blur outset is the blurriness, whichever way it runs — what a '
      'group buffer must grow by', () {
    expect(resolveCompositeEffectPaint([blur(6)]).outsetPixels, 6);
    expect(resolveCompositeEffectPaint([blur(9, dimensions: 2)]).outsetPixels, 9);
    const bounds = ui.Rect.fromLTWH(0, 0, 10, 10);
    expect(
      effectBufferBounds(
        bounds,
        resolveCompositeEffectPaint([blur(4)]).outsetPixels,
      ),
      const ui.Rect.fromLTWH(-4, -4, 18, 18),
    );
    expect(
      effectBufferBounds(
        bounds,
        resolveCompositeEffectPaint([colour(brightness: 5)]).outsetPixels,
      ),
      bounds,
      reason: 'colour spreads nothing — no buffer growth, no wasted offscreen',
    );
  });

  test('🗣️I-132-Q3: Blur Dimensions says which way the blurriness runs', () {
    ui.ImageFilter? filterOf(int dimensions) =>
        resolveCompositeEffectPaint([
          blur(4, dimensions: dimensions),
        ]).imageFilter;
    ui.ImageFilter gaussian(double x, double y) => ui.ImageFilter.blur(
      sigmaX: x * blurSigmaPerRadius,
      sigmaY: y * blurSigmaPerRadius,
      tileMode: ui.TileMode.decal,
    );
    expect(filterOf(0), gaussian(4, 4), reason: 'Horizontal and Vertical');
    expect(filterOf(1), gaussian(4, 0), reason: 'Horizontal');
    expect(filterOf(2), gaussian(0, 4), reason: 'Vertical');
    expect(
      resolveCompositeEffectPaint([blur(0, dimensions: 2)]).isEmpty,
      isTrue,
      reason: 'no blurriness is no blur, whichever way it would run',
    );
  });

  test('the draw space scales the BLUR and leaves colour alone', () {
    final full = resolveCompositeEffectPaint([blur(12, dimensions: 1)]);
    final half = resolveCompositeEffectPaint([blur(12, dimensions: 1)], space: const DrawSpace.preScaled(0.5));
    expect(half.outsetPixels, 6);
    expect(full.outsetPixels, 12);
    expect(
      half.imageFilter,
      ui.ImageFilter.blur(
        sigmaX: 6 * blurSigmaPerRadius,
        sigmaY: 0,
        tileMode: ui.TileMode.decal,
      ),
      reason: 'a half-size playback raster must not show a double blur',
    );
    // Colour is scale-free: the same filter at any raster.
    expect(
      resolveCompositeEffectPaint([
        colour(brightness: 20),
      ], space: const DrawSpace.preScaled(0.25)).colorFilter,
      resolveCompositeEffectPaint([colour(brightness: 20)]).colorFilter,
    );
  });

  test('applyTo writes exactly one field and refuses to fight a tint', () {
    final colourPaint = ui.Paint();
    resolveCompositeEffectPaint([colour(brightness: 5)]).applyTo(colourPaint);
    expect(colourPaint.colorFilter, isNotNull);
    expect(colourPaint.imageFilter, isNull);

    final blurPaint = ui.Paint();
    resolveCompositeEffectPaint([blur(3)]).applyTo(blurPaint);
    expect(blurPaint.imageFilter, isNotNull);
    expect(blurPaint.colorFilter, isNull);

    // An onion ghost's tint owns the colorFilter slot; effects must never
    // arrive on that paint (the assert is the contract, not a suggestion).
    final ghost = ui.Paint()
      ..colorFilter = const ui.ColorFilter.mode(
        ui.Color(0xFF00FF00),
        ui.BlendMode.srcIn,
      );
    expect(
      () => resolveCompositeEffectPaint([colour(brightness: 5)]).applyTo(ghost),
      throwsA(isA<AssertionError>()),
    );
    // …and a ghost's EMPTY chain is a no-op, which is why it never fires.
    expect(() => CompositeEffectPaint.none.applyTo(ghost), returnsNormally);
  });
}
