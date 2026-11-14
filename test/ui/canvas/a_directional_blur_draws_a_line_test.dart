import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/directional_blur_passes.dart';

/// 🗣️I-132-Q3 · Q8 (유저 2026-10-27): AE's Directional Blur — every pixel the
/// average of the line through it, [blurLength] across; 0° up, clockwise,
/// so 0° blurs up and down.
///
/// What a chain asks of it: passes that make one box, and a step of its
/// own as far as half its line. ↩️What a dot becomes through it was held
/// here on the Flutter chain (`DirectionalBlurShader`) till it went
/// (the-flutter-fx-chain-is-a-second-chain): the engine's line blur holds
/// it now (rust/src/kernels/effects/blur/line_tests.rs), and a row blurred
/// along a way, at rest and turned, laid as the walk painted it
/// (the_engine_lays_a_tree_as_the_walk_paints_it_test).
void main() {
  ResolvedLayerEffect directional({
    required double degrees,
    required double length,
  }) => ResolvedLayerEffect(
    kind: EffectKind.directionalBlur,
    values: [degrees, length],
  );

  group('the passes make one box', () {
    for (final length in [1.0, 1.5, 7.0, 32.0, 33.0, 500.0, 1024.0, 1025.0]) {
      test('$length long', () {
        final passes = directionalBlurPasses(dx: 0.6, dy: -0.8, length: length);
        final taps = passes.first.taps;
        expect(passes.map((pass) => pass.taps).toSet(), {taps});
        expect(taps, inInclusiveRange(1, lineBoxTapsAPass));
        final samples = math.pow(taps, passes.length);
        expect(
          samples,
          greaterThanOrEqualTo(length),
          reason: 'a sample every pixel at most — no gap between two',
        );
        expect(
          passes.length == 1 ||
              math.pow(lineBoxTapsAPass, passes.length - 1) < length,
          isTrue,
          reason: 'the fewest passes that reach it',
        );
        for (var index = 0; index < passes.length; index += 1) {
          final pass = passes[index];
          final step = math.sqrt(
            pass.stepX * pass.stepX + pass.stepY * pass.stepY,
          );
          expect(
            step * math.pow(taps, passes.length - index),
            closeTo(length, 1e-9),
            reason: 'each pass N times the one before, the last across '
                'the length',
          );
          expect(pass.stepX * 0.8, closeTo(-pass.stepY * 0.6, 1e-9));
        }
      });
    }
  });

  group('the plan', () {
    test('a blur of no length is no step, whichever way it points', () {
      final plan = resolveCompositeEffectPlan([
        directional(degrees: 37, length: 0),
      ], paper: Rect.zero);
      expect(plan.isSingleDraw, isTrue);
      expect(plan.finalEffects, isEmpty);
    });

    test('it is a step of its own, and grows the buffer half the line each '
        'way', () {
      final plan = resolveCompositeEffectPlan([
        directional(degrees: 90, length: 40),
      ], paper: Rect.zero);
      expect(plan.preSteps, hasLength(1));
      expect(plan.preSteps.single.lead, isA<ShadedEffect>());
      expect(plan.preSteps.single.then, isEmpty);
      expect(plan.finalEffects, isEmpty);
      expect(plan.outsetPixels, 21);
    });

    test('what comes before it is a step before it, and what follows it the '
        'draw after', () {
      final blur = ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: const [3, 3],
      );
      final plan = resolveCompositeEffectPlan([
        blur,
        directional(degrees: 90, length: 40),
        blur,
      ], paper: Rect.zero);
      expect([for (final step in plan.preSteps) step.lead.runtimeType], [
        Null,
        ShadedEffect,
      ]);
      expect(plan.preSteps.first.then, [blur]);
      expect(plan.finalEffects, [blur]);
      expect(
        plan.outsetPixels,
        21 + 2 * 3,
      );
    });
  });
}
