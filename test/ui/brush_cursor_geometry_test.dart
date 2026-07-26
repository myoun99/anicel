import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_point.dart';
import 'package:quick_animaker_v2/src/models/canvas_viewport.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_cursor_geometry.dart';

/// Screen position of a canvas point, computed straight from the viewport
/// contract rather than from the geometry helper — the axes are checked
/// against an INDEPENDENT formula, so a shared mistake cannot pass.
({double x, double y}) screenDelta(
  CanvasViewport viewport,
  double dx,
  double dy,
) {
  final origin = viewport.canvasToViewport(CanvasPoint(x: 0, y: 0));
  final moved = viewport.canvasToViewport(CanvasPoint(x: dx, y: dy));
  return (x: moved.x - origin.x, y: moved.y - origin.y);
}

void main() {
  group('brushCursorShape', () {
    test('a round tip at 100% is half the brush size in every direction', () {
      final shape = brushCursorShape(
        viewport: CanvasViewport(),
        size: 40,
        roundness: 1,
        angleDegrees: 0,
      )!;

      expect(shape.majorRadius, closeTo(20, 1e-9));
      expect(shape.minorRadius, closeTo(20, 1e-9));
    });

    test('zoom scales the outline', () {
      final shape = brushCursorShape(
        viewport: CanvasViewport(zoom: 2.5),
        size: 40,
        roundness: 1,
        angleDegrees: 0,
      )!;

      expect(shape.majorRadius, closeTo(50, 1e-9));
    });

    test('roundness flattens the minor axis only', () {
      final shape = brushCursorShape(
        viewport: CanvasViewport(),
        size: 40,
        roundness: 0.25,
        angleDegrees: 0,
      )!;

      expect(shape.majorRadius, closeTo(20, 1e-9));
      expect(shape.minorRadius, closeTo(5, 1e-9));
    });

    test('a positive angle points the major axis up-right (y-down)', () {
      // The P15 convention the rasterizers use: the cursor has to agree
      // with where the ellipse actually paints.
      final shape = brushCursorShape(
        viewport: CanvasViewport(),
        size: 40,
        roundness: 0.3,
        angleDegrees: 45,
      )!;

      expect(shape.majorAxis.dx, greaterThan(0));
      expect(shape.majorAxis.dy, lessThan(0));
      // The axes stay perpendicular, which is what lets the painter draw a
      // plain rotated oval.
      final dot =
          shape.majorAxis.dx * shape.minorAxis.dx +
          shape.majorAxis.dy * shape.minorAxis.dy;
      expect(dot, closeTo(0, 1e-9));
    });

    test('a rotated viewport turns the outline with the canvas', () {
      final viewport = CanvasViewport(rotationDegrees: 90);
      final shape = brushCursorShape(
        viewport: viewport,
        size: 40,
        roundness: 0.3,
        angleDegrees: 0,
      )!;

      final expected = screenDelta(viewport, 20, 0);
      expect(shape.majorAxis.dx, closeTo(expected.x, 1e-9));
      expect(shape.majorAxis.dy, closeTo(expected.y, 1e-9));
    });

    test('a flipped viewport mirrors the outline', () {
      final viewport = CanvasViewport(flipHorizontal: true);
      final shape = brushCursorShape(
        viewport: viewport,
        size: 40,
        roundness: 0.3,
        angleDegrees: 30,
      )!;

      final radians = 30 * math.pi / 180;
      final expected = screenDelta(
        viewport,
        20 * math.cos(radians),
        -20 * math.sin(radians),
      );
      expect(shape.majorAxis.dx, closeTo(expected.x, 1e-9));
      expect(shape.majorAxis.dy, closeTo(expected.y, 1e-9));
    });

    test('too small on screen yields no outline (crosshair stands in)', () {
      // A 2px brush at 100%, and a 40px brush zoomed far out: both are
      // unreadable as an outline for the same reason.
      expect(
        brushCursorShape(
          viewport: CanvasViewport(),
          size: 2,
          roundness: 1,
          angleDegrees: 0,
        ),
        isNull,
      );
      expect(
        brushCursorShape(
          viewport: CanvasViewport(zoom: 0.1),
          size: 40,
          roundness: 1,
          angleDegrees: 0,
        ),
        isNull,
      );
    });

    test('zooming IN brings a small brush back as an outline', () {
      expect(
        brushCursorShape(
          viewport: CanvasViewport(zoom: 8),
          size: 2,
          roundness: 1,
          angleDegrees: 0,
        ),
        isNotNull,
      );
    });

    test('the threshold reads the LONG axis, so a flat tip still shows', () {
      // A calligraphy nib is a few pixels across and long: judging it by
      // the minor axis would hide the outline exactly where the angle
      // matters most.
      final shape = brushCursorShape(
        viewport: CanvasViewport(),
        size: 40,
        roundness: 0.05,
        angleDegrees: 0,
      );

      expect(shape, isNotNull);
      expect(shape!.minorRadius * 2, lessThan(minimumBrushCursorDiameter));
    });

    test('a nonsense size draws nothing rather than throwing', () {
      expect(
        brushCursorShape(
          viewport: CanvasViewport(),
          size: 0,
          roundness: 1,
          angleDegrees: 0,
        ),
        isNull,
      );
      expect(
        brushCursorShape(
          viewport: CanvasViewport(),
          size: double.nan,
          roundness: 1,
          angleDegrees: 0,
        ),
        isNull,
      );
    });
  });
}
