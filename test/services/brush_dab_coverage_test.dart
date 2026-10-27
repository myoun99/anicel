import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_pixel_coverage.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_coverage.dart';

/// asinh 1 = ln(1 + √2): the corner integral of a unit square.
final _asinhOfOne = math.log(1 + math.sqrt2);

void main() {
  BrushDab dab({
    double x = 10,
    double y = 10,
    double size = 4,
    double opacity = 1,
    double flow = 1,
    double hardness = 1,
    BrushTipShape tipShape = BrushTipShape.round,
    int sequence = 0,
    double roundness = 1.0,
    double angleDegrees = 0.0,
    BrushTipMask? tipMask,
    BrushAntiAlias antiAlias = BrushAntiAlias.high,
  }) {
    return BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF000000,
      size: size,
      opacity: opacity,
      flow: flow,
      hardness: hardness,
      tipShape: tipShape,
      pressure: 1,
      sequence: sequence,
      roundness: roundness,
      angleDegrees: angleDegrees,
      tipMask: tipMask,
      antiAlias: antiAlias,
    );
  }

  // ↩️I-50: at 3단계 a nib smaller than the step's edge is all edge, so the
  // pins on a HARD nib's own disc read it at 없음 — the one step that adds
  // no edge and leaves full coverage full.
  const noEdge = BrushAntiAlias.none;

  // Left half fully opaque, right half transparent: orientation-revealing.
  final halfMask = BrushTipMask(
    id: 'half',
    size: 8,
    alpha: Uint8List.fromList([
      for (var y = 0; y < 8; y += 1)
        for (var x = 0; x < 8; x += 1)
          if (x < 4) 255 else 0,
    ]),
  );

  group('🚨one walk, two shapes', () {
    // The list form is the visitor with a list on the end. Two transcriptions
    // of this cascade is exactly what the no-copies rule forbids — and a
    // behaviour test cannot see a second one, because two copies that agree
    // today pass everything. What it CAN see is that the two forms answer
    // the same, pixel for pixel, in the same order.
    //
    // ⚠️The visitor exists because the list allocates one object per covered
    // pixel and copies the lot: one bake of the brush roster made 8,480,380
    // of them (2026-09-10). It must never become a second implementation.
    test('the list form is the visitor with a list on the end', () {
      final cases = <(String, BrushDab)>[
        ('round', dab()),
        ('soft', dab(hardness: 0.2, size: 9)),
        ('squashed and turned', dab(roundness: 0.35, angleDegrees: 37)),
        ('sampled tip', dab(tipMask: halfMask, size: 10)),
        ('sub-pixel centre', dab(x: 10.37, y: 9.61, size: 5.5)),
        ('faint', dab(opacity: 0.05, flow: 0.05, size: 6)),
      ];

      for (final entry in cases) {
        final visited = <BrushPixelCoverage>[];
        forEachBrushPixelCoverage(
          entry.$2,
          (x, y, coverage, ceiling) => visited.add(
            BrushPixelCoverage(
              x: x,
              y: y,
              coverage: coverage,
              ceiling: ceiling,
            ),
          ),
        );
        final listed = brushPixelCoveragesForDab(entry.$2);

        expect(
          listed.length,
          visited.length,
          reason: '${entry.$1}: the two forms cover a different pixel count',
        );
        expect(listed, isNotEmpty, reason: '${entry.$1}: fixture covers nothing');
        for (var index = 0; index < listed.length; index += 1) {
          expect(
            listed[index],
            visited[index],
            reason: '${entry.$1}: pixel $index differs between the two forms',
          );
        }
      }
    });

    test('⛔a dab that covers nothing visits nothing', () {
      // The list form answers `[]` here; the visitor must not call at all,
      // or a consumer folding into a plane would fold a phantom pixel.
      for (final empty in <BrushDab>[
        dab(size: 0),
        dab(opacity: 0),
        dab(flow: 0),
      ]) {
        var calls = 0;
        forEachBrushPixelCoverage(empty, (_, _, _, _) => calls += 1);
        expect(calls, 0);
        expect(brushPixelCoveragesForDab(empty), isEmpty);
      }
    });
  });

  group('brushPixelCoveragesForDab', () {
    test('returns empty list for zero-size dab', () {
      expect(brushPixelCoveragesForDab(dab(size: 0)), isEmpty);
    });

    test('returns empty list for zero-opacity dab', () {
      expect(brushPixelCoveragesForDab(dab(opacity: 0)), isEmpty);
    });

    test('returns empty list for zero-flow dab', () {
      expect(brushPixelCoveragesForDab(dab(flow: 0)), isEmpty);
    });

    test('square tip covers all pixels in dirty region with coverage 1', () {
      expect(
        brushPixelCoveragesForDab(
          dab(x: 1, y: 1, size: 2, tipShape: BrushTipShape.square),
        ),
        [
          BrushPixelCoverage(x: 0, y: 0, coverage: 1),
          BrushPixelCoverage(x: 1, y: 0, coverage: 1),
          BrushPixelCoverage(x: 0, y: 1, coverage: 1),
          BrushPixelCoverage(x: 1, y: 1, coverage: 1),
        ],
      );
    });

    test('square tip returns pixels in row-major order', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 1, y: 1, size: 2, tipShape: BrushTipShape.square),
      );
      expect(values.map((value) => (value.x, value.y)), [
        (0, 0),
        (1, 0),
        (0, 1),
        (1, 1),
      ]);
    });

    test('round hard tip skips pixels outside radius', () {
      expect(
        brushPixelCoveragesForDab(
          dab(x: 1, y: 1, size: 1, hardness: 1, antiAlias: noEdge),
        ),
        isEmpty,
      );
    });

    test('at a step, a pixel\'s square past the rim takes its share — a dot '
        'at four pixels\' corner, a quarter of its area each', () {
      // Q6 b: a small round tip is read under a pixel's WHOLE square, so a
      // dot lays its area wherever it lies. ↩️Read along the radius (Q4) a
      // pixel reached half a pixel past the rim and no further, and a dot
      // of 0.4 at the corner, its centres 0.707 out, laid nothing at all.
      final past = brushPixelCoveragesForDab(
        dab(x: 1, y: 1, size: 1, hardness: 1),
      );
      expect(past, hasLength(4));
      expect(past.every((c) => c.coverage > 0 && c.coverage < 0.5), isTrue);
      final dot = brushPixelCoveragesForDab(
        dab(x: 1, y: 1, size: 0.4, hardness: 1),
      );
      expect(dot, hasLength(4));
      expect(
        dot.map((c) => c.coverage),
        everyElement(closeTo(math.pi * 0.2 * 0.2 / 4, 0.0005)),
        reason: 'each square holds a quarter of the dot',
      );
    });

    test('round hard tip gives coverage 1 inside radius', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 1, y: 1, size: 2, hardness: 1, antiAlias: noEdge),
      );
      expect(values, hasLength(4));
      expect(values.every((value) => value.coverage == 1), isTrue);
    });

    test('round soft tip gives lower coverage near edge', () {
      // 1단계's edge is narrower than this ramp, so the ramp is the
      // hardness's own (I-50: 「경도 램프가 더 넓으면 그쪽」).
      final values = brushPixelCoveragesForDab(
        dab(
          x: 10,
          y: 10,
          size: 4,
          hardness: 0.5,
          antiAlias: BrushAntiAlias.low,
        ),
      );
      final nearCenter = values.firstWhere(
        (value) => value.x == 9 && value.y == 9,
      );
      final nearEdge = values.firstWhere(
        (value) => value.x == 8 && value.y == 9,
      );
      // The square of the pixel by the centre — (0, 0)–(1, 1) from it — is
      // whole where it lies within 1 of it and loses the ramp's (r − 1)
      // past that, out to the corner at √2: 2·∫₀^{π/4} ∫₁^{sec θ}
      // (r − 1) r dr dθ = 2·((√2 + asinh 1)/6 − 1/2 + π/24) of it (Q6 b).
      // ↩️0.979 while a pixel was read along the radius (Q4).
      expect(
        nearCenter.coverage,
        closeTo(
          1 - 2 * ((math.sqrt2 + _asinhOfOne) / 6 - 0.5 + math.pi / 24),
          0.00001,
        ),
      );
      expect(nearEdge.coverage, allOf(greaterThan(0), lessThan(1)));
      expect(nearEdge.coverage, lessThan(nearCenter.coverage));
    });

    test('round hardness 1 produces hard coverage', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 10, y: 10, size: 4, hardness: 1, antiAlias: noEdge),
      );
      expect(values, isNotEmpty);
      expect(values.every((value) => value.coverage == 1), isTrue);
    });

    test('round hardness 0 produces radial falloff', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 10, y: 10, size: 4, hardness: 0),
      );
      final nearCenter = values.firstWhere(
        (value) => value.x == 9 && value.y == 9,
      );
      final nearEdge = values.firstWhere(
        (value) => value.x == 8 && value.y == 9,
      );
      // The cone 1 − r/2 over the pixel's square by the centre: one less
      // half the square's mean distance from its corner, (√2 + asinh 1)/3
      // (Q6 b). ↩️At its centre's distance alone, 1 − 0.707/2, while a pixel
      // was read along the radius (Q4).
      expect(
        nearCenter.coverage,
        closeTo(1 - (math.sqrt2 + _asinhOfOne) / 6, 0.00001),
      );
      expect(nearEdge.coverage, lessThan(nearCenter.coverage));
    });

    test('elliptical tip flattens the minor axis at angle 0', () {
      // Size 10 (radius 5), roundness 0.4 -> minor radius 2: pixels along
      // the horizontal major axis stay covered out to the full radius while
      // vertical pixels beyond the minor radius drop out.
      final values = brushPixelCoveragesForDab(
        dab(x: 10.5, y: 10.5, size: 10, roundness: 0.4),
      );
      final coords = values.map((value) => (value.x, value.y)).toSet();
      expect(coords, contains((14, 10))); // dx=+4 along major axis
      expect(coords, contains((6, 10))); // dx=-4 along major axis
      expect(coords, isNot(contains((10, 14)))); // dy=+4 beyond minor radius
      expect(coords, isNot(contains((10, 6)))); // dy=-4 beyond minor radius
      expect(coords, contains((10, 11))); // dy=+1 within minor radius
    });

    test('elliptical tip at angle 90 swaps the axes', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 10.5, y: 10.5, size: 10, roundness: 0.4, angleDegrees: 90),
      );
      final coords = values.map((value) => (value.x, value.y)).toSet();
      expect(coords, contains((10, 14))); // vertical is now the major axis
      expect(coords, contains((10, 6)));
      expect(coords, isNot(contains((14, 10)))); // horizontal is now minor
      expect(coords, isNot(contains((6, 10))));
    });

    test('elliptical tip at 45 degrees tilts the major axis up-right', () {
      // Visual counterclockwise angle in y-down screen coordinates: the
      // major axis at 45 degrees runs toward (+x, -y).
      final values = brushPixelCoveragesForDab(
        dab(x: 10.5, y: 10.5, size: 12, roundness: 0.3, angleDegrees: 45),
      );
      final coords = values.map((value) => (value.x, value.y)).toSet();
      expect(coords, contains((13, 7))); // up-right along the major axis
      expect(coords, contains((7, 13))); // down-left along the major axis
      expect(coords, isNot(contains((13, 13)))); // perpendicular: outside
      expect(coords, isNot(contains((7, 7))));
    });

    test('full roundness keeps the classic circle regardless of angle', () {
      final baseline = brushPixelCoveragesForDab(
        dab(x: 10.3, y: 9.8, size: 6, hardness: 0.5),
      );
      final rotated = brushPixelCoveragesForDab(
        dab(x: 10.3, y: 9.8, size: 6, hardness: 0.5, angleDegrees: 73),
      );
      expect(rotated, baseline);
    });

    test('sampled tip covers only where the mask has alpha', () {
      // Size 8 (radius 4), half-opaque mask at angle 0: pixels left of the
      // center are covered, pixels right of it are not.
      final values = brushPixelCoveragesForDab(
        dab(x: 10.5, y: 10.5, size: 8, tipMask: halfMask),
      );
      final coords = values.map((value) => (value.x, value.y)).toSet();
      expect(coords, contains((8, 10))); // dx=-2 -> opaque left half
      expect(coords, isNot(contains((13, 10)))); // dx=+3 -> transparent half
      expect(values.every((value) => value.coverage > 0), isTrue);
    });

    test('sampled tip rotates with angle', () {
      // At 90 degrees (visual CCW) the opaque half turns to face
      // downward in y-down screen coordinates: tipU = -dy for dx=0, so
      // pixels BELOW the center map to the mask's opaque (negative-u) half.
      final values = brushPixelCoveragesForDab(
        dab(x: 10.5, y: 10.5, size: 8, tipMask: halfMask, angleDegrees: 90),
      );
      final coords = values.map((value) => (value.x, value.y)).toSet();
      expect(coords, contains((10, 12))); // below center -> covered
      expect(coords, isNot(contains((10, 8)))); // above center -> transparent
    });

    test('sampled tip ignores hardness and tipShape', () {
      final soft = brushPixelCoveragesForDab(
        dab(x: 10.5, y: 10.5, size: 8, tipMask: halfMask, hardness: 0.0),
      );
      final hardSquare = brushPixelCoveragesForDab(
        dab(
          x: 10.5,
          y: 10.5,
          size: 8,
          tipMask: halfMask,
          hardness: 1.0,
          tipShape: BrushTipShape.square,
        ),
      );
      expect(soft, hardSquare);
    });

    test('fractional center includes pixels exactly on radius boundary', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 10.5, y: 10.5, size: 2, hardness: 1, antiAlias: noEdge),
      );
      expect(values.map((value) => (value.x, value.y)), [
        (10, 9),
        (9, 10),
        (10, 10),
        (11, 10),
        (10, 11),
      ]);
    });

    test('coverage values are clamped to 0..1', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 10, y: 10, size: 4, hardness: 0),
      );
      expect(values, isNotEmpty);
      expect(
        values.every((value) => value.coverage >= 0 && value.coverage <= 1),
        isTrue,
      );
    });

    test('returns unmodifiable list if practical', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 1, y: 1, size: 2, tipShape: BrushTipShape.square),
      );
      expect(
        () => values.add(BrushPixelCoverage(x: 9, y: 9, coverage: 1)),
        throwsUnsupportedError,
      );
    });

    test('does not mutate BrushDab', () {
      final value = dab(x: 10, y: 10, size: 4, hardness: 0.5);
      final before = value.copyWith();
      brushPixelCoveragesForDab(value);
      expect(value, before);
    });

    test('does not access BitmapTile or BitmapSurface', () {
      final values = brushPixelCoveragesForDab(dab());
      expect(values, isA<List<BrushPixelCoverage>>());
    });
  });
}
