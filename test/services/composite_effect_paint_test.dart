import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/color_matrix.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';

/// The ONE translation from resolved effect samples to what a draw paints
/// (R6): what the engine lays (composite_tree_plan.dart), so its contract
/// is where every row agrees — or would silently disagree.
///
/// ↩️It was pinned on the Skia paint it folded into
/// (`resolveCompositeEffectPaint`) till the Flutter chain went
/// (the-flutter-fx-chain-is-a-second-chain).
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

  CompositeEffectPlan planOf(List<ResolvedLayerEffect> effects) =>
      resolveCompositeEffectPlan(
        effects,
        paper: const ui.Rect.fromLTWH(0, 0, 64, 48),
      );

  test('an empty chain paints nothing and grows no buffer', () {
    expect(paintedEffectsOf(const []), isEmpty);
    final plan = planOf(const []);
    expect(plan.finalEffects, isEmpty);
    expect(plan.outsetPixels, 0);
  });

  test('a colour-only chain is one matrix — no offscreen', () {
    final painted = paintedEffectsOf([colour(brightness: 20)]);
    expect(
      (painted.single as PaintedColour).matrix,
      brightnessContrastMatrix(brightness: 20, contrast: 0),
      reason: 'the matrix IS the math core — no second implementation here',
    );
    expect(planOf([colour(brightness: 20)]).outsetPixels, 0);
  });

  test('two colour effects FOLD into one matrix', () {
    final painted = paintedEffectsOf([
      colour(brightness: 10),
      ResolvedLayerEffect(kind: EffectKind.hueSaturation, values: [0, -100, 0]),
    ]);
    expect(
      (painted.single as PaintedColour).matrix,
      composeColorMatrices(
        hueSaturationMatrix(hueDegrees: 0, saturation: -100, lightness: 0),
        brightnessContrastMatrix(brightness: 10, contrast: 0),
      ),
      reason: 'list order = application order, folded outer∘inner',
    );
  });

  test('a chain that resolves to the identity is dropped', () {
    // Reachable through clamping and through a hue rotation of 360.
    final plan = planOf([
      ResolvedLayerEffect(kind: EffectKind.hueSaturation, values: [360, 0, 0]),
    ]);
    expect(plan.finalEffects, isEmpty);
    expect(plan.isSingleDraw, isTrue);
  });

  test('a blur paints after the colour before it, in the chain\'s order', () {
    expect(paintedEffectsOf([colour(brightness: 20), blur(6, dimensions: 1)]), [
      isA<PaintedColour>(),
      isA<GaussianBlur>(),
    ]);
    expect(
      planOf([colour(brightness: 20), blur(6, dimensions: 1)]).finalEffects,
      hasLength(2),
    );
  });

  test('the blur outset is the blurriness, whichever way it runs — what a '
      'group buffer must grow by', () {
    expect(planOf([blur(6)]).outsetPixels, 6);
    expect(planOf([blur(9, dimensions: 2)]).outsetPixels, 9);
    const bounds = ui.Rect.fromLTWH(0, 0, 10, 10);
    expect(
      effectBufferBounds(bounds, planOf([blur(4)]).outsetPixels),
      const ui.Rect.fromLTWH(-4, -4, 18, 18),
    );
    expect(
      effectBufferBounds(bounds, planOf([colour(brightness: 5)]).outsetPixels),
      bounds,
      reason: 'colour spreads nothing — no buffer growth, no wasted offscreen',
    );
  });

  test('blurs one over another reach as far as their reaches together', () {
    expect(planOf([blur(4), colour(brightness: 5), blur(6)]).outsetPixels, 10);
  });

  // How far the engine's weights reach and how far its chain puts past
  // what it reads are one number (composite_tree_plan.dart): the walk
  // lies too far off the Gaussian to tell a pixel short (mutants D06 ·
  // D20, 11-08).
  test('a Gaussian between whole pixels reaches the next whole one, and '
      'none the way it does not run', () {
    GaussianBlur only(ResolvedLayerEffect effect) =>
        paintedEffectsOf([effect]).single as GaussianBlur;
    expect(only(blur(2.5, dimensions: 1)).wholeReach, (3, 0));
    expect(only(blur(4)).wholeReach, (4, 4));
  });

  test('🗣️I-132-Q3: Blur Dimensions says which way the blurriness runs', () {
    (double, double) sigmasOf(int dimensions) => switch (paintedEffectsOf([
      blur(4, dimensions: dimensions),
    ]).single) {
      GaussianBlur(:final sigmaX, :final sigmaY) => (sigmaX, sigmaY),
      final other => throw StateError('$other'),
    };
    const sigma = 4 * blurSigmaPerRadius;
    expect(sigmasOf(0), (sigma, sigma), reason: 'Horizontal and Vertical');
    expect(sigmasOf(1), (sigma, 0.0), reason: 'Horizontal');
    expect(sigmasOf(2), (0.0, sigma), reason: 'Vertical');
    expect(
      planOf([blur(0, dimensions: 2)]).finalEffects,
      isEmpty,
      reason: 'no blurriness is no blur, whichever way it would run',
    );
  });
}
