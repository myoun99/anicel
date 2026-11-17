import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/brush_dab_share.dart';

import '../helpers/a_mixing_stroke_on_the_engine.dart';

/// Board `mixing-strength-follows-the-dab-spacing` (2026-10-24): a mixing
/// brush lifts its share of a stamp's pickup ([stampShareOf]) — the flow's
/// law (유저 2026-10-01 「엔진이 쌓임을 환산 — 크기와 무관하게(클튜처럼)」 ·
/// 「모든 브러시」) — so one 색 늘이기 drags as far at every spacing. Since
/// the brush is refilled (gouache card Q8, 2026-10-30) the refill is its
/// share of a stamp's too, so one 물감량 comes back as soon.
void main() {
  BrushDab dab(double x, {required double size, double? pathStep}) =>
      BrushDab(
        center: CanvasPoint(x: x, y: 64),
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

  // White where x is under 256, bare canvas from 300 on — a dab of 20
  // there lies wholly on it.
  const canvas = CanvasSize(width: 512, height: 128);
  final ground = aGroundOf(canvas, (x, _) => x < 256 ? 0xFFFFFFFF : 0);
  const bareFrom = 300.0;

  BrushShape mixing({required double paintAmount}) => BrushShape(
    mixesGroundColor: true,
    paintAmount: paintAmount,
    paintDensity: 1,
    colorStretch: 0.1,
  );

  /// The dabs of a brush 20 px across along [length] px from [from], one
  /// every [step].
  List<BrushDab> along(
    double length, {
    required double step,
    double from = 20,
  }) => [
    for (var x = step; x <= length + 1e-9; x += step)
      dab(from + x, size: 20, pathStep: step),
  ];

  /// What [stroke] lays of [dabs] — as one batch — last.
  BrushDab last(AMixingStroke stroke, List<BrushDab> dabs) {
    try {
      return stroke.lay(dabs).last;
    } finally {
      stroke.end();
    }
  }

  /// What a black brush of [shape] lays last over [length] px of white.
  BrushDab lastOverWhite(
    BrushShape shape,
    double length, {
    required double step,
  }) => last(
    AMixingStroke(shape, ground: ground),
    along(length, step: step),
  );

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
      expect(
        alphaOf(lastOverWhite(mixing(paintAmount: 0), length, step: step)),
        closeTo(whole, 1),
        reason: 'dry, a dab every $step px: 1 − 0.892⁵ of the white',
      );
      // So little paint that its refill does not count.
      final loaded = mixing(paintAmount: 0.05);
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
      final stroke = AMixingStroke(mixing(paintAmount: 1), ground: ground);
      // Loaded with the white by taps, then over bare canvas.
      for (var tap = 0; tap < 6; tap += 1) {
        stroke.lay([dab(20, size: 20)]);
      }
      return redOf(last(stroke, along(length, step: step, from: bareFrom)));
    }

    final tenth = cameBack(2);
    expect(tenth, inInclusiveRange(25, 45), reason: 'premise: half back');
    expect(cameBack(1), closeTo(tenth, 2));
    expect(cameBack(0.5), closeTo(tenth, 3));
  });

  test('a dab that stands for no path — a tap, the first — lifts a whole '
      'stamp', () {
    int lifted(double? pathStep) => alphaOf(
      last(AMixingStroke(mixing(paintAmount: 0), ground: ground), [
        dab(20, size: 20, pathStep: pathStep),
      ]),
    );

    expect(lifted(null), lifted(2));
    expect(lifted(null), greaterThan(lifted(1)));
  });
}
