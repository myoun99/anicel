import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/shaded_passes.dart';

/// 🗣️I-132-Q3 (유저 2026-10-27): AE's Camera Lens Blur; 🗣️I-132-Q15 a
/// (10-28): 「모든 모양을 정확히 — 행 누적합」 — every pixel the mean of the
/// pixels about it its iris covers.
///
/// What a chain asks of it: a step of its own, as far as its radius, on
/// the paper's whole pixels. ↩️What it draws was held here on the Flutter
/// chain (`IrisBlurShader`) till it went (the-flutter-fx-chain-is-a-second-
/// chain): the engine's lens blur holds it now — its table to the shape
/// (rust/src/kernels/effects/blur/iris_tests.rs), its sums and gather by
/// hand and the ledger (gather_tests.rs, lens_tests.rs), and a row through
/// it laid as the walk painted it
/// (the_engine_lays_a_tree_as_the_walk_paints_it_test).
void main() {
  ResolvedLayerEffect lens({
    required double radius,
    int shape = 3,
    double roundness = 0,
    double fringe = 0,
    bool repeats = false,
  }) => ResolvedLayerEffect(
    kind: EffectKind.cameraLensBlur,
    values: [
      for (final spec in EffectKind.cameraLensBlur.parameters)
        {
              'blurRadius': radius,
              'irisShape': shape.toDouble(),
              'irisRoundness': roundness,
              'irisDiffractionFringe': fringe,
              'repeatEdgePixels': repeats ? 1.0 : 0.0,
            }[spec.id] ??
            spec.defaultValue,
    ],
  );

  const paper = Rect.fromLTWH(0, 0, 64, 64);

  test('no radius is no step, whatever the iris', () {
    final plan = resolveCompositeEffectPlan([
      lens(radius: 0, shape: 0, roundness: 50, fringe: 300),
    ], paper: paper);
    expect(plan.isSingleDraw, isTrue);
    expect(plan.finalEffects, isEmpty);
  });

  test('it reaches its radius past its input', () {
    expect(
      resolveCompositeEffectPlan([lens(radius: 37.5)], paper: paper)
          .outsetPixels,
      37.5,
    );
  });

  test('the paper whose edge it repeats is on whole pixels', () {
    final iris =
        shadedPassesOf(
              lens(radius: 8, shape: 1, roundness: 20, repeats: true),
              paper: const Rect.fromLTWH(20.4, 9.6, 70, 30),
            ).last
            as IrisGatherPass;
    expect(iris.paper, const Rect.fromLTRB(20, 10, 90, 40));
  });
}
