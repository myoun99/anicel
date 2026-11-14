import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/directional_blur_passes.dart';
import 'package:anicel/src/services/shaded_passes.dart';

/// 🗣️I-132-Q3 (유저 2026-10-27): AE's Radial Blur — every pixel the average
/// of the arc through it about its centre (Spin, Amount in degrees) or of
/// the ray through it from there (Zoom); 🗣️I-132-Q12 b: the centre is a
/// point of its own, at rest the paper's middle; 🗣️I-132-Q13 a: Draft
/// takes fewer samples.
///
/// What a chain asks of it: a step of its own as far as the paper's
/// farthest corner moves, about its centre where the paper lies. ↩️What a
/// dot becomes through it — on a circle about the centre, or on its ray —
/// was held here on the Flutter chain (`DirectionalBlurShader`) till it
/// went (the-flutter-fx-chain-is-a-second-chain): the engine's line blur
/// holds its taps (rust/src/kernels/effects/blur/line_tests.rs), and a row
/// spun and a row zoomed about a point laid as the walk painted them
/// (the_engine_lays_a_tree_as_the_walk_paints_it_test).
void main() {
  const paper = Rect.fromLTWH(0, 0, 128, 128);

  ResolvedLayerEffect radial({
    required double amount,
    bool zoom = false,
    bool draft = false,
    CanvasPoint? center,
  }) => ResolvedLayerEffect(
    kind: EffectKind.radialBlur,
    values: [amount, 0, if (zoom) 1 else 0, if (draft) 1 else 0],
    points: {'center': center},
  );

  group('the plan', () {
    test('no amount is no step, whichever way it turns', () {
      for (final zoom in [false, true]) {
        final plan = resolveCompositeEffectPlan([
          radial(amount: 0, zoom: zoom),
        ], paper: paper);
        expect(plan.isSingleDraw, isTrue);
        expect(plan.finalEffects, isEmpty);
      }
    });

    test('it reaches as far as the paper\'s farthest corner moves', () {
      final corner = math.sqrt(64 * 64 * 2);
      expect(
        resolveCompositeEffectPlan([
          radial(amount: 90),
        ], paper: paper).outsetPixels,
        closeTo(2 * corner * math.sin(math.pi / 8) + 1, 1e-9),
        reason: 'a quarter turn: the chord of its half',
      );
      expect(
        resolveCompositeEffectPlan([
          radial(amount: 50, zoom: true),
        ], paper: paper).outsetPixels,
        closeTo(corner * (math.exp(0.25) - 1) + 1, 1e-9),
        reason: 'half the ray, out',
      );
      expect(
        resolveCompositeEffectPlan([
          radial(amount: 90, center: CanvasPoint(x: 0, y: 0)),
        ], paper: paper).outsetPixels,
        greaterThan(
          resolveCompositeEffectPlan([
            radial(amount: 90),
          ], paper: paper).outsetPixels,
        ),
        reason: 'a centre in the corner lies farther from the paper\'s far '
            'corner',
      );
    });

    test('Draft takes one pass; Best as many as a sample every pixel out at '
        'the far corner asks', () {
      List<LineBoxPass> passes({required bool draft}) => shadedPassesOf(
        radial(amount: 90, draft: draft),
        paper: paper,
      ).cast();
      final best = passes(draft: false);
      final draft = passes(draft: true);

      expect(draft, hasLength(1));
      expect(best.length, greaterThan(1));
      final arc = math.pi / 2 * math.sqrt(64 * 64 * 2);
      final samples = best.fold<int>(1, (product, pass) => product * pass.taps);
      expect(samples, greaterThanOrEqualTo(arc.ceil()));
      // And Zoom's: the ray of the pixel it draws out farthest — half the
      // ray past the far corner — from that corner to as far again out.
      final zoom = shadedPassesOf(
        radial(amount: 50, zoom: true),
        paper: paper,
      ).cast<LineBoxPass>();
      final ray = math.sqrt(64 * 64 * 2) * (math.exp(0.5) - 1);
      expect(
        zoom.fold<int>(1, (product, pass) => product * pass.taps),
        greaterThanOrEqualTo(ray.ceil()),
      );
      expect(draft.single.taps, lineBoxTapsAPass);
      expect(
        {for (final pass in [...best, ...draft]) (pass.centerX, pass.centerY)},
        {(64.0, 64.0)},
        reason: 'about the paper\'s middle, in the raster\'s pixels',
      );
    });

    test('its centre in the raster is where the paper lies there', () {
      final passes = shadedPassesOf(
        radial(amount: 30, center: CanvasPoint(x: 10, y: 20)),
        paper: const Rect.fromLTWH(8, 4, 128, 128),
      ).cast<LineBoxPass>();

      expect(passes.first.centerX, 8 + 10);
      expect(passes.first.centerY, 4 + 20);
    });
  });

  test('a line is still a line: a directional blur\'s passes neither turn '
      'nor grow', () {
    for (final pass in directionalBlurPasses(dx: 0, dy: 1, length: 500)) {
      expect((pass.turn, pass.grow, pass.centerX, pass.centerY), (0, 0, 0, 0));
    }
  });
}
