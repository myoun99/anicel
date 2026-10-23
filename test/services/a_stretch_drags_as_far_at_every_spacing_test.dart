import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/brush_dab_share.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';

/// Board `mixing-strength-follows-the-dab-spacing` (2026-10-24): a mixing
/// brush lifts its share of a stamp's pickup ([stampShareOf]) — the flow's
/// law (유저 2026-10-01 「엔진이 쌓임을 환산 — 크기와 무관하게(클튜처럼)」 ·
/// 「모든 브러시」) — so one 색 늘이기 drags as far at every spacing.
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

  /// The red the reservoir holds after a black brush of [size] crosses
  /// [length] px of white ground, a dab every [step] px — read off the last
  /// deposit, which a brush releasing all its paint lays as it holds it.
  int draggedOver(double length, {required double step, double size = 20}) {
    final mixer = BrushGroundColorMixer(
      shape: const BrushShape(
        mixesGroundColor: true,
        paintAmount: 1,
        paintDensity: 1,
        colorStretch: 0.1,
      ),
    );
    final laid = mixer.apply(
      [
        for (var x = step; x <= length + 1e-9; x += step)
          dab(x, size: size, pathStep: step),
      ],
      sample: (_, _, _) =>
          const BrushGroundSample(rgb: 0xFFFFFF, coverage: 1),
    );
    return (laid.last.color >> 16) & 0xFF;
  }

  test('🚨one stretch drags as far a dab a pixel apart as a dab a tenth of '
      'the size apart', () {
    // Size 20: a tenth is 2 px. Ten pixel-apart dabs used to lift 0.1 ten
    // times (to 166) where five tenth-apart ones lifted it five (to 105).
    final tenth = draggedOver(10, step: 2);
    expect(
      tenth,
      closeTo(255 * (1 - math.pow(0.9, 5)), 2),
      reason: 'five whole stamps of 0.1: 1 − 0.9⁵, each dab rounded',
    );
    expect(draggedOver(10, step: 1), closeTo(tenth, 2));
    expect(draggedOver(10, step: 0.5), closeTo(tenth, 3));
  });

  test('a dab that stands for no path — a tap, the first — lifts its '
      'stretch whole', () {
    final mixer = BrushGroundColorMixer(
      shape: const BrushShape(
        mixesGroundColor: true,
        paintAmount: 1,
        paintDensity: 1,
        colorStretch: 0.5,
      ),
    );
    final laid = mixer.apply(
      [dab(0, size: 20)],
      sample: (_, _, _) =>
          const BrushGroundSample(rgb: 0xFFFFFF, coverage: 1),
    );
    expect((laid.single.color >> 16) & 0xFF, 128);
  });

  test('every mixing preset lifts, at its own size, what it lifted per dab '
      'before', () {
    // The stretches before a dab lifted its share (2026-10-24): what one
    // dab took at the preset's own size and spacing.
    const before = {
      'builtin-pastel': 0.4,
      'builtin-wet-watercolor': 0.4,
      'builtin-dense-watercolor': 0.3,
      'builtin-flat-wash': 0.35,
      'builtin-oil-brush': 0.4,
      'builtin-palette-knife': 0.5,
      'builtin-blender': 0.35,
      'builtin-water-blend': 0.3,
      'builtin-blending-stump': 0.35,
    };
    final mixing = [
      for (final preset in defaultBrushPresets)
        if (preset.settings.mixesGroundColor) preset,
    ];
    expect(
      {for (final preset in mixing) preset.id.value},
      before.keys.toSet(),
      reason: 'a mixing preset not in the table was never fitted',
    );
    for (final preset in mixing) {
      final s = preset.settings;
      final step = const BrushDabInterpolator().spacingForBrushSize(
        s.size,
        s.spacing,
      );
      final share = stampShareOf(dab(0, size: s.size, pathStep: step));
      expect(
        1 - math.pow(1 - s.colorStretch, share),
        closeTo(before[preset.id.value]!, 0.0005),
        reason: '${preset.id.value} at ${s.size}px (share $share)',
      );
    }
  });
}
