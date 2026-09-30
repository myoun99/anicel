import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/selection_affine.dart';
import 'package:anicel/src/services/transform_box_law.dart';

/// F-222 ①: the box law's solves, asked directly — the transform tool, the
/// camera frame and the layer box all take their numbers from here.
void main() {
  group('wholePixels', () {
    test('rounds the TOTAL travel to whole canvas pixels', () {
      final moved = TransformBoxLaw.wholePixels(CanvasPoint(x: 3.33, y: -2.6));
      expect(moved.x, 3);
      expect(moved.y, -3);
    });
  });

  group('turn', () {
    final centre = CanvasPoint(x: 100, y: 100);

    test('reads the pointer on the canvas: right of the centre is 0°, below '
        'it is 90° (clockwise, y down)', () {
      expect(
        TransformBoxLaw.angleAbout(centre, CanvasPoint(x: 150, y: 100)),
        0,
      );
      expect(
        TransformBoxLaw.angleAbout(centre, CanvasPoint(x: 100, y: 150)),
        closeTo(90, 1e-9),
      );
    });

    test('a step across the ±180° seam is the small turn the hand made', () {
      // From just above the left (-170°) to just below it (170°): the hand
      // went 20° anticlockwise, not 340° clockwise.
      final step = TransformBoxLaw.turn(
        centre: centre,
        pointer: CanvasPoint(x: 0, y: 100 + 17.6327),
        lastAngle: -170,
      );
      expect(step.angle, closeTo(170, 1e-3));
      expect(step.turned, closeTo(-20, 1e-3));
    });

    test('steps add up past a whole turn', () {
      var last = TransformBoxLaw.angleAbout(
        centre,
        CanvasPoint(x: 150, y: 100),
      );
      var total = 0.0;
      // Clockwise in quarter steps, five of them: 450°.
      for (final pointer in [
        CanvasPoint(x: 100, y: 150),
        CanvasPoint(x: 50, y: 100),
        CanvasPoint(x: 100, y: 50),
        CanvasPoint(x: 150, y: 100),
        CanvasPoint(x: 100, y: 150),
      ]) {
        final step = TransformBoxLaw.turn(
          centre: centre,
          pointer: pointer,
          lastAngle: last,
        );
        last = step.angle;
        total += step.turned;
      }
      expect(total, closeTo(450, 1e-9));
    });
  });

  group('scaled', () {
    // A 100×50 box centred on (200, 100), untouched.
    final start = SelectionAffine(pivot: CanvasPoint(x: 200, y: 100));
    final bottomRight = CanvasPoint(x: 50, y: 25);

    test('about the centre by default: the centre stays, the box grows both '
        'ways', () {
      // The bottom-right corner (250, 125) pulled to (300, 150): twice as
      // far from the centre.
      final result = TransformBoxLaw.scaled(
        start,
        bottomRight,
        CanvasPoint(x: 300, y: 150),
        aboutCentre: true,
        uniform: true,
      );
      expect(result.sx, closeTo(2, 1e-9));
      expect(result.sy, closeTo(2, 1e-9));
      expect(result.apply(CanvasPoint(x: 200, y: 100)).x, closeTo(200, 1e-9));
      expect(result.apply(CanvasPoint(x: 200, y: 100)).y, closeTo(100, 1e-9));
    });

    test('about the opposite corner otherwise: that corner stays put', () {
      // Top-left (150, 75) stays; bottom-right (250, 125) → (350, 175).
      final result = TransformBoxLaw.scaled(
        start,
        bottomRight,
        CanvasPoint(x: 350, y: 175),
        aboutCentre: false,
        uniform: true,
      );
      expect(result.sx, closeTo(2, 1e-9));
      final topLeft = result.apply(CanvasPoint(x: 150, y: 75));
      expect(topLeft.x, closeTo(150, 1e-9));
      expect(topLeft.y, closeTo(75, 1e-9));
    });

    test('uniform takes the closest fit on the diagonal, not the larger axis',
        () {
      // Off the diagonal: x asks 3×, y asks 1×. The least-squares fit sits
      // between them; the larger axis would have been 3.
      final result = TransformBoxLaw.scaled(
        start,
        bottomRight,
        CanvasPoint(x: 350, y: 125),
        aboutCentre: true,
        uniform: true,
      );
      expect(result.sx, result.sy);
      const fit = (150 * 50 + 25 * 25) / (50 * 50 + 25 * 25);
      expect(result.sx, closeTo(fit, 1e-9));
      expect(fit, allOf(greaterThan(1), lessThan(3)));
    });

    test('not uniform: each axis takes its own scale', () {
      final result = TransformBoxLaw.scaled(
        start,
        bottomRight,
        CanvasPoint(x: 350, y: 125),
        aboutCentre: true,
        uniform: false,
      );
      expect(result.sx, closeTo(3, 1e-9));
      expect(result.sy, closeTo(1, 1e-9));
    });
  });

  group('pressDisplaced', () {
    test('moves the grabbed handle by the hand\'s travel, not onto the hand',
        () {
      final start = SelectionAffine(pivot: CanvasPoint(x: 200, y: 100));
      // The press landed 10 px left of the bottom-right corner (250, 125).
      final point = TransformBoxLaw.pressDisplaced(
        start,
        CanvasPoint(x: 50, y: 25),
        CanvasPoint(x: 240, y: 125),
        CanvasPoint(x: 260, y: 130),
      );
      expect(point.x, closeTo(270, 1e-9));
      expect(point.y, closeTo(130, 1e-9));
    });
  });

  group('clampScale', () {
    test('keeps a scale off zero with its sign, and off NaN', () {
      expect(TransformBoxLaw.clampScale(0), 0.01);
      expect(TransformBoxLaw.clampScale(-0.001), -0.01);
      expect(TransformBoxLaw.clampScale(double.nan), 0.01);
      expect(TransformBoxLaw.clampScale(1.5), 1.5);
    });
  });
}
