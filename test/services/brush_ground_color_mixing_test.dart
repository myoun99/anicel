import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';

import '../helpers/a_mixing_stroke_on_the_engine.dart';

/// A dab carrying [color] at ([x], 64); only colour, position, size and
/// [pressure] matter here. It stands for no path, so it takes a whole
/// stamp's pickup and refill.
BrushDab dabAt(double x, int color, {double pressure = 1.0}) => BrushDab(
  center: CanvasPoint(x: x, y: 64),
  color: color,
  size: 10,
  opacity: 1.0,
  flow: 1.0,
  hardness: 1.0,
  tipShape: BrushTipShape.round,
  pressure: pressure,
  sequence: 0,
);

const _canvas = CanvasSize(width: 512, height: 128);

/// A cel of [argb] where x is under 256, bare canvas past it — where the
/// dabs from [bareFrom] lie.
BitmapSurface groundOf(int argb) =>
    aGroundOf(_canvas, (x, _) => x < 256 ? argb : 0);

/// The first x of bare canvas a dab of [dabAt]'s lies wholly on.
const double bareFrom = 300;

final BitmapSurface bare = aGroundOf(_canvas, (_, _) => 0);

int redOf(BrushDab dab) => (dab.color >> 16) & 0xFF;

int alphaOf(BrushDab dab) => (dab.color >> 24) & 0xFF;

/// What [shape] lays of [dabs] over [ground], each dab a batch of its own.
List<BrushDab> laid(
  BrushShape shape,
  BitmapSurface ground,
  List<BrushDab> dabs, {
  math.Random? random,
}) {
  final stroke = AMixingStroke(shape, ground: ground, random: random);
  try {
    return [for (final dab in dabs) ...stroke.lay([dab])];
  } finally {
    stroke.end();
  }
}

void main() {
  const red = 0xFFFF0000;
  const black = 0xFF000000;
  const blue = 0xFF0000FF;
  const white = 0xFFFFFFFF;

  BrushShape mixing({
    double paintAmount = 1.0,
    double paintDensity = 1.0,
    double colorStretch = 0.0,
  }) => BrushShape(
    mixesGroundColor: true,
    paintAmount: paintAmount,
    paintDensity: paintDensity,
    colorStretch: colorStretch,
  );

  /// The red channel of what a black brush of [shape] lays over white
  /// ground, [over] dabs, and then over bare canvas, [after] dabs.
  List<int> blackOverWhite(BrushShape shape, {int over = 1, int after = 0}) =>
      laid(shape, groundOf(white), [
        for (var i = 0; i < over; i += 1) dabAt(20 + i * 10.0, black),
        for (var i = 0; i < after; i += 1) dabAt(bareFrom + i * 10.0, black),
      ]).map(redOf).toList();

  test('a brush that does not mix returns its dabs untouched', () {
    final mixer = BrushGroundColorMixer(shape: const BrushShape());
    final dabs = [dabAt(0, red)];

    expect(mixer.apply(dabs), same(dabs));
  });

  test('a loaded brush on bare canvas lays its own colour', () {
    // Transparent pixels have RGB 0; letting them into what the brush
    // carries would drag every stroke toward black.
    expect(laid(mixing(), bare, [dabAt(20, white)]).single.color, white);
  });

  test('🎯a stamp lifts the ground, is refilled with its colour, and lays '
      'that colour over what it carries', () {
    // A black brush over white, one whole stamp at 색 늘이기 0 and 물감량 1:
    // it lifts 0.12 of the white (31), is refilled 0.12 back toward black
    // (27), and lays 0.3 of black over that (19) — the numbers fitted to
    // the user's Clip Studio strokes.
    expect(blackOverWhite(mixing()), [19]);
  });

  test('🎯the higher the colour stretch, the less a stamp lifts — and at 1 '
      'it lifts nothing', () {
    // Clip Studio's 색 늘이기: the higher, the further a picked-up colour is
    // drawn out. ↩️It was how much a stamp lifted until 2026-10-30.
    final none = blackOverWhite(mixing()).single;
    final half = blackOverWhite(mixing(colorStretch: 0.5)).single;
    final all = blackOverWhite(mixing(colorStretch: 1.0)).single;

    expect(none, greaterThan(half));
    expect(half, greaterThan(0));
    expect(all, 0, reason: 'lays its own colour, as on bare canvas');
  });

  test('🎯over bare canvas a loaded brush comes back to its own colour — '
      'the sooner, the more paint it holds', () {
    final full = blackOverWhite(mixing(), over: 6, after: 12);
    final half = blackOverWhite(mixing(paintAmount: 0.5), over: 6, after: 12);

    for (final laid in [full, half]) {
      final carried = laid.sublist(6);
      expect(carried.first, greaterThan(0), reason: 'it carries the white');
      for (var i = 1; i < carried.length; i += 1) {
        expect(carried[i], lessThan(carried[i - 1]), reason: '$laid');
      }
    }
    expect(full.last, lessThan(full[6] / 3), reason: '$full');
    expect(
      full.last / full[6],
      lessThan(half.last / half[6]),
      reason: 'more paint refills it faster: $full · $half',
    );
  });

  test('partial ground coverage lifts less than solid ground', () {
    final solid = blackOverWhite(mixing()).single;
    final partial = redOf(
      laid(mixing(), groundOf(0x80FFFFFF), [dabAt(20, black)]).single,
    );

    expect(partial, greaterThan(0));
    expect(partial, lessThan(solid));
  });

  test('paint density scales the dab alpha, not its colour', () {
    final thin = laid(mixing(paintDensity: 0.5), groundOf(blue), [
      dabAt(20, red),
    ]).single;
    final full = laid(mixing(), groundOf(blue), [dabAt(20, red)]).single;

    expect(alphaOf(thin), 0x80);
    expect(thin.color & 0xFFFFFF, full.color & 0xFFFFFF);
  });

  test('what the brush carries runs on across the dabs of one batch and '
      'the next', () {
    // Ordering is load-bearing: the rasterizers may never reorder dabs in a
    // mixing stroke.
    final stroke = AMixingStroke(mixing(), ground: groundOf(white));
    final batched = stroke
        .lay([dabAt(20, black), dabAt(30, black)])
        .map(redOf)
        .toList();
    stroke.end();

    expect(batched[1], greaterThan(batched[0]));
    expect(blackOverWhite(mixing(), over: 2), batched);
  });

  test('a copy of a dab — symmetry\'s, a second tip\'s — lays its '
      'original\'s colour, and the brush moves once for both', () {
    final stroke = AMixingStroke(mixing(), ground: groundOf(white));
    final laid = stroke.lay(
      [dabAt(20, black), dabAt(30, black)],
      copied: (mixed) => [
        for (final dab in mixed) ...[
          dab,
          dab.copyWith(
            center: CanvasPoint(x: dab.center.x + 180, y: dab.center.y),
          ),
        ],
      ],
    );
    stroke.end();

    final reds = laid.map(redOf).toList();
    final once = blackOverWhite(mixing(), over: 2);
    expect(reds, [once[0], once[0], once[1], once[1]]);
  });

  group('a dry brush — no paint of its own', () {
    // 수채 섞기 (유저, gouache card Q8): 「필압 최대로 그려도 색이 안 나옴,
    // 다른 칠해진 색을 섞을 뿐」.
    final dry = mixing(paintAmount: 0.0);

    test('lays nothing on bare canvas', () {
      expect(laid(dry, bare, [dabAt(20, red), dabAt(30, red)]).map(alphaOf), [
        0,
        0,
      ]);
    });

    test('🎯lays what it picks up, thicker the longer it rubs, and thins '
        'over bare canvas', () {
      final dabs = laid(dry, groundOf(blue), [
        for (var i = 0; i < 4; i += 1) dabAt(20 + i * 10.0, red),
        for (var i = 0; i < 4; i += 1) dabAt(bareFrom + i * 10.0, red),
      ]);

      expect(
        dabs.map((dab) => dab.color & 0xFFFFFF),
        everyElement(blue & 0xFFFFFF),
        reason: 'the ground\'s colour, never its own red',
      );
      final alphas = dabs.map(alphaOf).toList();
      expect(alphas.first, 31, reason: 'a stamp lifts 0.12 of the ground');
      for (var i = 1; i < 4; i += 1) {
        expect(alphas[i], greaterThan(alphas[i - 1]), reason: '$alphas');
      }
      for (var i = 5; i < 8; i += 1) {
        expect(alphas[i], lessThan(alphas[i - 1]), reason: '$alphas');
      }
    });

    test('at colour stretch 1 lifts nothing, so lays nothing', () {
      final dabs = laid(
        mixing(paintAmount: 0.0, colorStretch: 1.0),
        groundOf(blue),
        [dabAt(20, red), dabAt(30, red)],
      );

      expect(dabs.map(alphaOf), [0, 0]);
    });
  });

  group('絵の具量 and 絵の具濃度 follow the pen (gouache card Q9 = a)', () {
    // 유저 2026-10-30 「필압 줄을 넣는다」 — the same rows size and flow
    // have; Clip Studio's 불투명 수채 · 투명 수채 · 구아슈 carry them.
    BrushShape pressing(BrushPressureTarget target, BrushInputSource source) =>
        BrushShape(
          mixesGroundColor: true,
          curves: {(target, source): BrushPressureCurve.linearFrom(0.0)},
        );

    test('a lighter touch lays thinner paint', () {
      final shape = pressing(
        BrushPressureTarget.paintDensity,
        BrushInputSource.pressure,
      );
      final light = laid(shape, bare, [dabAt(20, red, pressure: 0.5)]);
      final hard = laid(shape, bare, [dabAt(20, red, pressure: 1.0)]);

      expect(alphaOf(light.single), 0x80);
      expect(alphaOf(hard.single), 0xFF);
    });

    test('🎯a lighter touch lays less of its own colour over what it '
        'crosses', () {
      final shape = pressing(
        BrushPressureTarget.paintAmount,
        BrushInputSource.pressure,
      );
      int redLaid(double pressure) => redOf(
        laid(shape, groundOf(white), [
          dabAt(20, black, pressure: pressure),
        ]).single,
      );

      expect(redLaid(0.2), greaterThan(redLaid(1.0)));
    });

    test('⚠️a load pressed down to nothing still lays what the brush '
        'carries — dry is the brush\'s 絵の具量, not the dab\'s', () {
      final shape = pressing(
        BrushPressureTarget.paintAmount,
        BrushInputSource.pressure,
      );

      expect(laid(shape, bare, [dabAt(20, red, pressure: 0.0)]).single.color,
          red);
    });

    test('the ランダム row throws the stroke\'s own dice, and is skipped '
        'without them', () {
      final shape = pressing(
        BrushPressureTarget.paintDensity,
        BrushInputSource.random,
      );
      final dabs = [for (var i = 0; i < 4; i += 1) dabAt(20 + i * 10.0, red)];
      final dice = math.Random(7);

      expect(
        laid(shape, bare, dabs, random: math.Random(7)).map(alphaOf),
        [for (var i = 0; i < 4; i += 1) (dice.nextDouble() * 255).round()],
      );
      expect(laid(shape, bare, dabs).map(alphaOf), everyElement(0xFF));
    });

    test('the built-in mixing brushes keep their values, with no such '
        'row', () {
      final pressed = [
        for (final preset in defaultBrushPresets)
          for (final (target, _) in preset.settings.shape.curves.keys)
            if (target == BrushPressureTarget.paintAmount ||
                target == BrushPressureTarget.paintDensity)
              preset.id.value,
      ];

      expect(pressed, isEmpty);
    });
  });
}
