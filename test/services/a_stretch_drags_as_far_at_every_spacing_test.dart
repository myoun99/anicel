import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_share.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';

/// Board `mixing-strength-follows-the-dab-spacing` (2026-10-24): a mixing
/// brush lifts its share of a stamp's pickup ([stampShareOf]) — the flow's
/// law (유저 2026-10-01 「엔진이 쌓임을 환산 — 크기와 무관하게(클튜처럼)」 ·
/// 「모든 브러시」) — so one 색 늘이기 drags as far at every spacing. Since
/// the brush is refilled (gouache card Q8, 2026-10-30) the refill is its
/// share of a stamp's too, so one 물감량 comes back as soon.
void main() {
  BrushDab dab(double x, {required double size, double? pathStep}) =>
      BrushDab(
        center: CanvasPoint(x: x, y: 0),
        color: 0xFF000000,
        size: size,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
        pathStep: pathStep,
      );

  const white = BrushGroundSample(rgb: 0xFFFFFF, coverage: 1);
  BrushGroundSample bare(double x, double y, double radius) =>
      BrushGroundSample.empty;

  BrushShape mixing({required double paintAmount}) => BrushShape(
    mixesGroundColor: true,
    paintAmount: paintAmount,
    paintDensity: 1,
    colorStretch: 0.1,
  );

  /// The dabs of a brush 20 px across along [length] px, one every [step].
  List<BrushDab> along(double length, {required double step}) => [
    for (var x = step; x <= length + 1e-9; x += step)
      dab(x, size: 20, pathStep: step),
  ];

  /// What a black [mixer] lays last over [length] px of white ground.
  BrushDab lastOverWhite(
    BrushGroundColorMixer mixer,
    double length, {
    required double step,
  }) => mixer.apply(along(length, step: step), sample: (_, _, _) => white)
      .last;

  int redOf(BrushDab laid) => (laid.color >> 16) & 0xFF;
  int alphaOf(BrushDab laid) => (laid.color >> 24) & 0xFF;

  // Size 20: a tenth is 2 px, so 10 px is five whole stamps. Taken whole by
  // every dab, ten pixel-apart dabs lifted ten stamps' worth.
  const length = 10.0;
  const pickPerStamp = 0.108; // (1 − 0.1) × 0.12: a stamp at 색 늘이기 0.1

  test('🚨one stretch lifts as far a dab a pixel apart as a dab a tenth of '
      'the size apart — dry, and loaded', () {
    final whole = 255 * (1 - math.pow(1 - pickPerStamp, 5));
    for (final step in [2.0, 1.0, 0.5]) {
      final dry = BrushGroundColorMixer(shape: mixing(paintAmount: 0));
      expect(
        alphaOf(lastOverWhite(dry, length, step: step)),
        closeTo(whole, 1),
        reason: 'dry, a dab every $step px: 1 − 0.892⁵ of the white',
      );
      // So little paint that its refill does not count.
      final loaded = BrushGroundColorMixer(shape: mixing(paintAmount: 0.05));
      expect(
        redOf(lastOverWhite(loaded, length, step: step)),
        closeTo(whole * (1 - 0.05 * 0.3), 3),
        reason: 'loaded, a dab every $step px',
      );
    }
  });

  test('🚨one paint amount comes back as soon a dab a pixel apart as a dab '
      'a tenth of the size apart', () {
    int cameBack(double step) {
      final mixer = BrushGroundColorMixer(shape: mixing(paintAmount: 1));
      // Loaded with the white by taps, then over bare canvas.
      for (var tap = 0; tap < 6; tap += 1) {
        mixer.apply([dab(0, size: 20)], sample: (_, _, _) => white);
      }
      return redOf(mixer.apply(along(length, step: step), sample: bare).last);
    }

    final tenth = cameBack(2);
    expect(tenth, inInclusiveRange(25, 45), reason: 'premise: half back');
    expect(cameBack(1), closeTo(tenth, 2));
    expect(cameBack(0.5), closeTo(tenth, 3));
  });

  test('a dab that stands for no path — a tap, the first — lifts a whole '
      'stamp', () {
    int lifted(double? pathStep) => alphaOf(
      BrushGroundColorMixer(shape: mixing(paintAmount: 0))
          .apply([
            dab(0, size: 20, pathStep: pathStep),
          ], sample: (_, _, _) => white)
          .single,
    );

    expect(lifted(null), lifted(2));
    expect(lifted(null), greaterThan(lifted(1)));
  });
}
