import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';

/// A dab carrying [color]; only colour, position and size matter here. It
/// stands for no path, so it takes a whole stamp's pickup and refill.
BrushDab dabAt(double x, int color) => BrushDab(
  center: CanvasPoint(x: x, y: 0),
  color: color,
  size: 10,
  opacity: 1.0,
  flow: 1.0,
  hardness: 1.0,
  tipShape: BrushTipShape.round,
  pressure: 1.0,
  sequence: 0,
);

BrushGroundColorSampler groundOf(int rgb, {double coverage = 1.0}) =>
    (_, _, _) => BrushGroundSample(rgb: rgb, coverage: coverage);

BrushGroundSample bare(double x, double y, double radius) =>
    BrushGroundSample.empty;

int redOf(BrushDab dab) => (dab.color >> 16) & 0xFF;

int alphaOf(BrushDab dab) => (dab.color >> 24) & 0xFF;

void main() {
  const red = 0xFFFF0000;
  const black = 0xFF000000;
  const blue = 0x0000FF;
  const white = 0xFFFFFF;

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
  List<int> blackOverWhite(BrushShape shape, {int over = 1, int after = 0}) {
    final mixer = BrushGroundColorMixer(shape: shape);
    return [
      for (var i = 0; i < over; i += 1)
        redOf(mixer.apply([dabAt(i * 10.0, black)], sample: groundOf(white))
            .single),
      for (var i = 0; i < after; i += 1)
        redOf(mixer.apply([dabAt(i * 10.0, black)], sample: bare).single),
    ];
  }

  test('a brush that does not mix returns its dabs untouched', () {
    final mixer = BrushGroundColorMixer(shape: const BrushShape());
    final dabs = [dabAt(0, red)];

    expect(mixer.apply(dabs, sample: groundOf(blue)), same(dabs));
  });

  test('a loaded brush on bare canvas lays its own colour', () {
    // Transparent pixels have RGB 0; letting them into what the brush
    // carries would drag every stroke toward black.
    final mixer = BrushGroundColorMixer(shape: mixing());

    expect(mixer.apply([dabAt(0, 0xFFFFFFFF)], sample: bare).single.color,
        0xFFFFFFFF);
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
    final mixer = BrushGroundColorMixer(shape: mixing());
    final partial = redOf(
      mixer
          .apply([dabAt(0, black)], sample: groundOf(white, coverage: 0.5))
          .single,
    );

    expect(partial, greaterThan(0));
    expect(partial, lessThan(solid));
  });

  test('paint density scales the dab alpha, not its colour', () {
    final thin = BrushGroundColorMixer(shape: mixing(paintDensity: 0.5))
        .apply([dabAt(0, red)], sample: groundOf(blue))
        .single;
    final full = BrushGroundColorMixer(shape: mixing())
        .apply([dabAt(0, red)], sample: groundOf(blue))
        .single;

    expect(alphaOf(thin), 0x80);
    expect(thin.color & 0xFFFFFF, full.color & 0xFFFFFF);
  });

  test('what the brush carries runs on across the dabs of one batch and '
      'the next', () {
    // Ordering is load-bearing: the rasterizers may never reorder dabs in a
    // mixing stroke.
    final batched = BrushGroundColorMixer(shape: mixing())
        .apply([dabAt(0, black), dabAt(10, black)], sample: groundOf(white))
        .map(redOf)
        .toList();

    expect(batched[1], greaterThan(batched[0]));
    expect(blackOverWhite(mixing(), over: 2), batched);
  });

  group('a dry brush — no paint of its own', () {
    // 수채 섞기 (유저, gouache card Q8): 「필압 최대로 그려도 색이 안 나옴,
    // 다른 칠해진 색을 섞을 뿐」.
    final dry = mixing(paintAmount: 0.0);

    test('lays nothing on bare canvas', () {
      final laid = BrushGroundColorMixer(shape: dry)
          .apply([dabAt(0, red), dabAt(10, red)], sample: bare);

      expect(laid.map(alphaOf), [0, 0]);
    });

    test('🎯lays what it picks up, thicker the longer it rubs, and thins '
        'over bare canvas', () {
      final mixer = BrushGroundColorMixer(shape: dry);
      final laid = [
        for (var i = 0; i < 4; i += 1)
          mixer.apply([dabAt(i * 10.0, red)], sample: groundOf(blue)).single,
        for (var i = 0; i < 4; i += 1)
          mixer.apply([dabAt(i * 10.0, red)], sample: bare).single,
      ];

      expect(
        laid.map((dab) => dab.color & 0xFFFFFF),
        everyElement(blue),
        reason: 'the ground\'s colour, never its own red',
      );
      final alphas = laid.map(alphaOf).toList();
      expect(alphas.first, 31, reason: 'a stamp lifts 0.12 of the ground');
      for (var i = 1; i < 4; i += 1) {
        expect(alphas[i], greaterThan(alphas[i - 1]), reason: '$alphas');
      }
      for (var i = 5; i < 8; i += 1) {
        expect(alphas[i], lessThan(alphas[i - 1]), reason: '$alphas');
      }
    });

    test('at colour stretch 1 lifts nothing, so lays nothing', () {
      final laid = BrushGroundColorMixer(
        shape: mixing(paintAmount: 0.0, colorStretch: 1.0),
      ).apply([dabAt(0, red), dabAt(10, red)], sample: groundOf(blue));

      expect(laid.map(alphaOf), [0, 0]);
    });
  });
}
