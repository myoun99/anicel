import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/draw_space.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/camera_lens_blur_passes.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/shaded_passes.dart';

/// 🗣️I-132-Q15 a (유저 2026-10-28): 「모든 모양을 정확히 — 행 누적합」 — a
/// camera lens blur's iris covers exactly the pixel centres its shape
/// holds, row by row ([irisSpans]), and each row is read out of its sums
/// ([rowSumPasses]).
///
/// The truth here is the shape asked point by point: how far the point
/// lies, unturned and unsqueezed, from the polygon drawn `1 - roundness` as
/// big — none of the crossings the spans are worked out from.
void main() {
  IrisProperties iris(
    int sides, {
    double roundness = 0,
    double aspect = 1,
    double rotation = 0,
    double fringe = 0,
  }) => (
    sides: sides,
    roundness: roundness,
    aspect: aspect,
    rotation: rotation,
    fringe: fringe,
  );

  /// Whether the pixel centre ([dx], [dy]) about the iris's own lies in
  /// [shape], [radius] out.
  bool inIris(int dx, int dy, double radius, IrisProperties shape) {
    final (:sides, :roundness, :aspect, :rotation, fringe: _) = shape;
    // Turned back, then unsqueezed.
    final (cos, sin) = (math.cos(rotation), math.sin(rotation));
    final x = (cos * dx + sin * dy) / math.min(aspect, 1.0);
    final y = (-sin * dx + cos * dy) / math.min(1 / aspect, 1.0);
    final corner = (1 - roundness) * radius;
    final corners = [
      for (var k = 0; k < sides; k += 1)
        (
          corner * math.cos(math.pi / 2 + math.pi / sides * (2 * k + 1)),
          corner * math.sin(math.pi / 2 + math.pi / sides * (2 * k + 1)),
        ),
    ];
    var inside = corner > 0;
    var nearest = double.infinity;
    for (var k = 0; k < sides; k += 1) {
      final (ax, ay) = corners[k];
      final (bx, by) = corners[(k + 1) % sides];
      // The corners run by a growing angle: the inside crosses positive.
      final cross = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
      if (cross < 0) {
        inside = false;
      }
      final (ex, ey) = (bx - ax, by - ay);
      final length = ex * ex + ey * ey;
      final t = length == 0
          ? 0.0
          : (((x - ax) * ex + (y - ay) * ey) / length).clamp(0.0, 1.0);
      final (px, py) = (ax + ex * t - x, ay + ey * t - y);
      nearest = math.min(nearest, math.sqrt(px * px + py * py));
    }
    return inside || nearest <= roundness * radius + 1e-9;
  }

  void expectExact(double radius, IrisProperties shape) {
    final reach = radius.floor();
    final spans = irisSpans(radius: radius, iris: shape, reach: reach);
    expect(spans, hasLength(2 * reach + 1));
    for (var dy = -reach; dy <= reach; dy += 1) {
      final covered = [
        for (var dx = -reach - 1; dx <= reach + 1; dx += 1)
          if (inIris(dx, dy, radius, shape)) dx,
      ];
      final span = spans[dy + reach];
      final spanned = [for (var dx = span.left; dx <= span.right; dx += 1) dx];
      expect(spanned, covered, reason: 'row $dy of $shape, r $radius');
    }
  }

  test('every shape, rounded, squeezed and turned, covers exactly the '
      'centres it holds', () {
    final random = math.Random(132);
    for (var trial = 0; trial < 300; trial += 1) {
      expectExact(
        0.5 + random.nextDouble() * 30,
        iris(
          3 + random.nextInt(8),
          roundness: switch (trial % 3) {
            0 => 0,
            1 => 1,
            _ => random.nextDouble(),
          },
          aspect: math.pow(10, random.nextDouble() * 2 - 1).toDouble(),
          rotation: (random.nextDouble() * 2 - 1) * math.pi,
        ),
      );
    }
  });

  test('a triangle points up and lies flat along its bottom', () {
    final spans = irisSpans(radius: 20, iris: iris(3), reach: 20);
    // Its bottom edge lies half its radius below the centre.
    final bottom = spans[20 + 10];
    expect(bottom.right - bottom.left, greaterThan(30));
    expect(spans[20 + 11].left, greaterThan(spans[20 + 11].right));
    final top = spans[0];
    expect(top.right - top.left, lessThanOrEqualTo(1), reason: 'a point');
  });

  test('a square stands square, and an aspect of 2 is twice as wide as '
      'tall', () {
    final half = (20 / math.sqrt2).floor();
    final square = irisSpans(radius: 20, iris: iris(4), reach: 20);
    for (var dy = -20; dy <= 20; dy += 1) {
      final span = square[dy + 20];
      expect(
        (span.left, span.right),
        dy.abs() <= half ? (-half, half) : (1, 0),
        reason: 'row $dy',
      );
    }
    final wide = irisSpans(radius: 20, iris: iris(4, aspect: 2), reach: 20);
    final rows = [
      for (var dy = -20; dy <= 20; dy += 1)
        if (wide[dy + 20].left <= wide[dy + 20].right) dy,
    ];
    expect(wide[20], (left: -half, right: half), reason: 'as wide');
    expect(rows.first, -(20 / math.sqrt2 / 2).floor(), reason: 'half as tall');
  });

  test('a turn is clockwise: a quarter turns the triangle to point right', () {
    final turned = irisSpans(
      radius: 20,
      iris: iris(3, rotation: math.pi / 2),
      reach: 20,
    );
    // Its point, out right on the middle row; its flat side, upright, half
    // its radius left of the centre.
    expect(turned[20].right, 20);
    expect(turned[20].left, -10);
  });

  test('a row sum covers every texel of its row up to it, in as few passes '
      'as 64 taps a pass make', () {
    for (final width in [1, 2, 63, 64, 65, 300, 4096, 4097]) {
      final passes = rowSumPasses(width);
      final taps = passes.first.taps;
      expect(passes.map((pass) => pass.taps).toSet(), {taps});
      expect(taps, inInclusiveRange(1, rowSumTapsAPass));
      if (passes.length > 1) {
        expect(math.pow(rowSumTapsAPass, passes.length - 1), lessThan(width));
      }
      // The passes run as `row_sum.frag` runs them, over a row of ones.
      var row = List<double>.filled(width, 1);
      for (final RowSumPass(:stride, :taps) in passes) {
        row = [
          for (var x = 0; x < width; x += 1)
            [
              for (var i = 0; i < taps && x - i * stride >= 0; i += 1)
                row[x - i * stride],
            ].fold(0.0, (sum, each) => sum + each),
        ];
      }
      expect(row, [for (var x = 0; x < width; x += 1) x + 1.0]);
    }
    expect(rowSumPasses(4096), hasLength(2));
    expect(rowSumPasses(4097), hasLength(3));
  });

  /// Read as stored, nothing boosted.
  const asStored = (
    gain: 0.0,
    threshold: 1.0,
    saturation: 0.0,
    linear: false,
  );

  group('the gather', () {
    IrisGatherPass gather(double radius, {double fringe = 0}) =>
        cameraLensBlurPasses(
              (
                radius: radius,
                iris: iris(6, roundness: 0.2, fringe: fringe),
                light: asStored,
              ),
              rasterWidth: 100,
              paper: null,
            ).last
            as IrisGatherPass;

    int covered(List<IrisSpan> rows) => rows.fold(
      0,
      (sum, row) => sum + math.max(0, row.right - row.left + 1),
    );

    test('weighs every pixel its iris covers alike without a fringe', () {
      final pass = gather(9.5);
      expect(pass.fringe, 0);
      expect(pass.core, isEmpty);
      expect(pass.weight, covered(pass.outline));
    });

    test('at 500 a fringe weighs its ring alone: all the light out of the '
        'core', () {
      final pass = gather(9.5, fringe: 500);
      expect(pass.fringe, 1);
      expect(pass.weight, covered(pass.outline) - covered(pass.core));
      expect(pass.weight, greaterThan(0));
      expect(gather(9.5, fringe: 100).fringe, 0.2);
    });

    test('an iris with no edge to push the light to has no fringe', () {
      expect(gather(0.5, fringe: 500).fringe, 0);
      expect(gather(0.5, fringe: 500).weight, 1);
    });
  });

  group('the light', () {
    List<ShadedPass> passesOf(LensLight light) => cameraLensBlurPasses(
      (radius: 6, iris: iris(5), light: light),
      rasterWidth: 300,
      paper: null,
    );

    LensLight? lightOf(List<ShadedPass> passes) =>
        (passes.last as IrisGatherPass).light;

    test('is read by the first row sum, of the picture, and the iris — not '
        'by the sums of sums', () {
      const boosted = (
        gain: 40.0,
        threshold: 0.8,
        saturation: 0.5,
        linear: false,
      );
      final passes = passesOf(boosted);
      final sums = passes.whereType<RowSumPass>().toList();
      expect(sums, hasLength(2), reason: 'fixture: 300 wide is two passes');
      expect(sums.first.stride, 1);
      expect(sums.first.light, boosted);
      expect(sums.last.light, isNull);
      expect(lightOf(passes), boosted);
    });

    test('is none where it is read as stored and nothing is boosted', () {
      expect(lightOf(passesOf(asStored)), isNull);
      LensLight boost(double gain, double threshold) => (
        gain: gain,
        threshold: threshold,
        saturation: 1,
        linear: false,
      );
      expect(lightOf(passesOf(boost(0, 0))), isNull, reason: 'no gain');
      expect(
        lightOf(passesOf(boost(40, 1))),
        isNull,
        reason: 'past white, nothing is boosted',
      );
      expect(lightOf(passesOf(boost(40, 0.99))), isNotNull);
      expect(
        passesOf(asStored).whereType<RowSumPass>().map((pass) => pass.light),
        everyElement(isNull),
      );
      const linear = (
        gain: 0.0,
        threshold: 1.0,
        saturation: 0.0,
        linear: true,
      );
      expect(lightOf(passesOf(linear)), linear, reason: 'linear light alone');
    });
  });

  group('the kind', () {
    const paper = ui.Rect.fromLTWH(0, 0, 64, 64);

    IrisGatherPass irisOf(List<double> values, {DrawSpace? space}) =>
        shadedPassesOf(
              ResolvedLayerEffect(
                kind: EffectKind.cameraLensBlur,
                values: values,
              ),
              space ?? DrawSpace.canvas,
              paper: paper,
              rasterWidth: 64,
            ).last
            as IrisGatherPass;

    test('reads its lanes as the iris: the menu its sides, a percent its '
        'roundness, degrees its turn, the fringe over 500', () {
      final shape = EffectKind.cameraLensBlur.parameterSpec('irisShape')!;
      expect(
        [for (final choice in shape.choices) choice.id],
        [
          'triangle',
          'square',
          'pentagon',
          'hexagon',
          'heptagon',
          'octagon',
          'nonagon',
          'decagon',
        ],
      );
      for (var index = 0; index < shape.choices.length; index += 1) {
        final pass = irisOf([
          12,
          index.toDouble(),
          30,
          1.4,
          25,
          200,
          ...[0, 255, 0, 0, 0],
        ]);
        expect(
          pass.outline,
          irisSpans(
            radius: 12,
            iris: iris(
              3 + index,
              roundness: 0.3,
              aspect: 1.4,
              rotation: 25 * math.pi / 180,
            ),
            reach: 12,
          ),
          reason: shape.choices[index].id,
        );
        expect(pass.fringe, 0.4);
        expect(pass.paper, isNull, reason: 'its edge repeats only when on');
        expect(pass.light, isNull, reason: 'no gain, read as stored');
      }
    });

    test('reads its Highlight lanes as the light: the threshold over 255, '
        'the saturation a percent, the gain as it is', () {
      expect(
        irisOf([12, 3, 0, 1, 0, 0, 40, 204, 50, 0, 1]).light,
        (gain: 40.0, threshold: 0.8, saturation: 0.5, linear: true),
      );
      expect(
        irisOf([12, 3, 0, 1, 0, 0, 0, 255, 0, 0, 1]).light?.linear,
        isTrue,
        reason: 'Use Linear Working Space alone',
      );
    });

    test('its radius is canvas pixels: a raster at twice the scale spans '
        'twice the rows', () {
      const flat = <double>[12, 3, 0, 1, 0, 0, 0, 255, 0, 0, 0];
      expect(irisOf(flat).reach, 12);
      expect(irisOf(flat, space: const DrawSpace.preScaled(2)).reach, 24);
    });

    test('begins at the Square, and at no blur', () {
      final effect = LayerEffect.defaults(
        id: const EffectId('lens'),
        kind: EffectKind.cameraLensBlur,
      );
      final shape = EffectKind.cameraLensBlur.parameterSpec('irisShape')!;
      expect(
        shape.choices[effect.parameters['irisShape']!.value.toInt()].id,
        'square',
      );
      expect(effect.parameters['blurRadius']!.value, 0);
    });

    test('begins with no highlight, read as stored', () {
      final effect = LayerEffect.defaults(
        id: const EffectId('lens'),
        kind: EffectKind.cameraLensBlur,
      );
      expect(
        {
          for (final id in [
            'highlightGain',
            'highlightThreshold',
            'highlightSaturation',
            'useLinearWorkingSpace',
          ])
            id: effect.parameters[id]!.value,
        },
        {
          'highlightGain': 0,
          'highlightThreshold': 255,
          'highlightSaturation': 0,
          'useLinearWorkingSpace': 0,
        },
      );
    });
  });
}
