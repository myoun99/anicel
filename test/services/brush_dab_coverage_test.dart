import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_pixel_coverage.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_coverage.dart';

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
    );
  }

  // Left half fully opaque, right half transparent: orientation-revealing.
  final halfMask = BrushTipMask(
    id: 'half',
    size: 8,
    alpha: Uint8List.fromList([
      for (var y = 0; y < 8; y += 1)
        for (var x = 0; x < 8; x += 1) x < 4 ? 255 : 0,
    ]),
  );

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
        brushPixelCoveragesForDab(dab(x: 1, y: 1, size: 1, hardness: 1)),
        isEmpty,
      );
    });

    test('round hard tip gives coverage 1 inside radius', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 1, y: 1, size: 2, hardness: 1),
      );
      expect(values, hasLength(4));
      expect(values.every((value) => value.coverage == 1), isTrue);
    });

    test('round soft tip gives lower coverage near edge', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 10, y: 10, size: 4, hardness: 0.5),
      );
      final nearCenter = values.firstWhere(
        (value) => value.x == 9 && value.y == 9,
      );
      final nearEdge = values.firstWhere(
        (value) => value.x == 8 && value.y == 9,
      );
      expect(nearCenter.coverage, 1);
      expect(nearEdge.coverage, allOf(greaterThan(0), lessThan(1)));
    });

    test('round hardness 1 produces hard coverage', () {
      final values = brushPixelCoveragesForDab(
        dab(x: 10, y: 10, size: 4, hardness: 1),
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
      expect(nearCenter.coverage, closeTo(1 - (0.70710678 / 2), 0.000001));
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

    test('rotated rectangle tip covers a diamond at 45 degrees', () {
      // Size 8 (radius 4), roundness 1, rotated 45 degrees: corners of the
      // axis-aligned bounding box fall outside the rotated square while the
      // axis midpoints stay inside.
      final values = brushPixelCoveragesForDab(
        dab(
          x: 10.5,
          y: 10.5,
          size: 8,
          tipShape: BrushTipShape.square,
          angleDegrees: 45,
        ),
      );
      final coords = values.map((value) => (value.x, value.y)).toSet();
      expect(coords, contains((10, 10)));
      expect(coords, contains((13, 10))); // axis midpoint stays inside
      expect(coords, contains((10, 13)));
      expect(coords, isNot(contains((13, 13)))); // bbox corner cut off
      expect(coords, isNot(contains((7, 7))));
      expect(values.every((value) => value.coverage == 1), isTrue);
    });

    test('rectangle roundness shrinks the minor side', () {
      final values = brushPixelCoveragesForDab(
        dab(
          x: 10.5,
          y: 10.5,
          size: 8,
          tipShape: BrushTipShape.square,
          roundness: 0.25,
        ),
      );
      final coords = values.map((value) => (value.x, value.y)).toSet();
      expect(coords, contains((13, 10))); // dx=+3 within the major half-width
      expect(coords, isNot(contains((10, 13)))); // dy=+3 beyond minor radius 1
      expect(coords, contains((10, 11))); // dy=+1 within minor radius
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
        dab(x: 10.5, y: 10.5, size: 2, hardness: 1),
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
