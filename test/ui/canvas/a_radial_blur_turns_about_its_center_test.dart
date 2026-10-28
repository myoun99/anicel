import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/draw_space.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/directional_blur_passes.dart';
import 'package:anicel/src/ui/canvas/directional_blur_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🗣️I-132-Q3 (유저 2026-10-27): AE's Radial Blur — every pixel the average
/// of the arc through it about its centre (Spin, Amount in degrees) or of
/// the ray through it from there (Zoom); 🗣️I-132-Q12 b: the centre is a
/// point of its own, at rest the paper's middle; 🗣️I-132-Q13 a: Draft
/// takes fewer samples.
///
/// A dot is the probe, as the directional blur's: what it becomes IS the
/// kernel — on a circle about the centre, or on its ray.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(DirectionalBlurShader.load);

  const side = 128;
  const paper = Rect.fromLTWH(0, 0, 128, 128);
  // The dot, 20 right of the paper's middle.
  const dotX = 84;
  const dotY = 64;

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

  ui.Image dot() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(dotX.toDouble(), dotY.toDouble(), 1, 1),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side, side);
    picture.dispose();
    return image;
  }

  Future<List<int>> blurred(WidgetTester tester, ResolvedLayerEffect effect) async {
    final source = dot();
    addTearDown(source.dispose);
    final out = steppedForChain(
      image: source,
      plan: resolveCompositeEffectPlan([effect], paper: paper),
      extent: paper,
      paper: paper,
    );
    if (!identical(out, source)) {
      addTearDown(out.dispose);
    }
    final data = await tester.runAsync(
      () => out.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    return [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
  }

  /// The most ink in the 3×3 pixels round ([x], [y]).
  int inkNear(List<int> alphas, int x, int y) => [
    for (var dy = -1; dy <= 1; dy += 1)
      for (var dx = -1; dx <= 1; dx += 1) alphas[(y + dy) * side + x + dx],
  ].reduce(math.max);

  /// The pixel [degrees] round the paper's middle from the dot, as far out.
  (int, int) round(double degrees) {
    final radians = degrees * math.pi / 180;
    return (
      (64 + 20 * math.cos(radians)).round(),
      (64 + 20 * math.sin(radians)).round(),
    );
  }

  group('Spin', () {
    testWidgets('spreads the dot along its circle, half the amount each way',
        (tester) async {
      final alphas = await blurred(tester, radial(amount: 90));
      final (inX, inY) = round(30);
      final (otherX, otherY) = round(-30);
      final (pastX, pastY) = round(60);

      expect(inkNear(alphas, inX, inY), greaterThan(0), reason: '30° on');
      expect(inkNear(alphas, otherX, otherY), greaterThan(0), reason: '−30°');
      expect(inkNear(alphas, pastX, pastY), 0, reason: 'past half of 90°');
      expect(
        inkNear(alphas, dotX + 8, dotY),
        0,
        reason: '⛔not out along its ray',
      );
    });

    testWidgets('about where its centre is keyed, not the paper\'s middle', (
      tester,
    ) async {
      final (inX, inY) = round(30);
      final alphas = await blurred(
        tester,
        radial(amount: 90, center: CanvasPoint(x: dotX + 0.5, y: dotY + 0.5)),
      );

      expect(
        inkNear(alphas, inX, inY),
        0,
        reason: 'the circle about the middle no longer runs through it',
      );
      expect(alphas[dotY * side + dotX], greaterThan(0), reason: 'kept');
    });
  });

  group('Zoom', () {
    testWidgets('spreads the dot along its ray, in and out', (tester) async {
      final alphas = await blurred(tester, radial(amount: 50, zoom: true));

      // At 50 the way out runs from e^−¼ to e^¼ of the dot's 20: 15.6 … 25.7.
      expect(inkNear(alphas, 64 + 17, dotY), greaterThan(0), reason: 'in');
      expect(inkNear(alphas, 64 + 24, dotY), greaterThan(0), reason: 'out');
      expect(inkNear(alphas, 64 + 12, dotY), 0, reason: 'past it, in');
      expect(inkNear(alphas, 64 + 29, dotY), 0, reason: 'past it, out');
      final (roundX, roundY) = round(20);
      expect(inkNear(alphas, roundX, roundY), 0, reason: '⛔not round');
    });
  });

  group('the plan', () {
    test('no amount is no step, whichever way it turns', () {
      for (final zoom in [false, true]) {
        final plan = resolveCompositeEffectPlan([
          radial(amount: 0, zoom: zoom),
        ], paper: paper);
        expect(plan.isSingleDraw, isTrue);
        expect(plan.finalPaint.isEmpty, isTrue);
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

    test('its reach is read in the space the plan is for', () {
      final once = resolveCompositeEffectPlan([
        radial(amount: 90),
      ], paper: paper).outsetPixels;
      final twice = resolveCompositeEffectPlan(
        [radial(amount: 90)],
        paper: paper,
        space: const DrawSpace.preScaled(2),
      ).outsetPixels;

      expect(twice - 1, closeTo((once - 1) * 2, 1e-9));
    });

    test('Draft takes one pass; Best as many as a sample every pixel out at '
        'the far corner asks', () {
      List<LineBoxPass> passes({required bool draft}) => shadedPassesOf(
        radial(amount: 90, draft: draft),
        DrawSpace.canvas,
        paper: paper,
      );
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
        DrawSpace.canvas,
        paper: paper,
      );
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
        const DrawSpace.preScaled(2),
        paper: const Rect.fromLTWH(8, 4, 256, 256),
      );

      expect(passes.first.centerX, 8 + 10 * 2);
      expect(passes.first.centerY, 4 + 20 * 2);
    });
  });

  test('a line is still a line: a directional blur\'s passes neither turn '
      'nor grow', () {
    for (final pass in directionalBlurPasses(dx: 0, dy: 1, length: 500)) {
      expect((pass.turn, pass.grow, pass.centerX, pass.centerY), (0, 0, 0, 0));
    }
  });
}
