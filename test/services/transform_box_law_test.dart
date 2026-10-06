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

    // 🗣️F-256 (유저 2026-10-01): 「변형도구 일반변형, 가로에 대한 단독배율변경
    // 같은게 저장안됨. 가로세로 통합으로서 … 기록됨」. 일반 has had edge
    // middles since 09-22, so a corner can meet a box whose two scales
    // differ — and it wrote ONE scale to both. 🧪2026-10-06: a 75×50 box
    // snapped to 64.5×64.5 on the first pixel of a corner drag.
    test('🚨uniform is one FACTOR for both axes — a corner keeps the '
        'proportions an edge middle gave the box', () {
      // Stretched to 150×50 by an edge: the corner stands at (275, 125).
      final stretched = SelectionAffine(
        pivot: CanvasPoint(x: 200, y: 100),
        sx: 1.5,
      );
      final still = TransformBoxLaw.scaled(
        stretched,
        bottomRight,
        CanvasPoint(x: 275, y: 125),
        aboutCentre: true,
        uniform: true,
      );
      expect(still.sx, closeTo(1.5, 1e-9), reason: 'a press moves nothing');
      expect(still.sy, closeTo(1, 1e-9));

      // Pulled twice as far from the centre along the box's own diagonal.
      final grown = TransformBoxLaw.scaled(
        stretched,
        bottomRight,
        CanvasPoint(x: 350, y: 150),
        aboutCentre: true,
        uniform: true,
      );
      expect(grown.sx, closeTo(3, 1e-9));
      expect(grown.sy, closeTo(2, 1e-9));

      // The same pull against the opposite corner, which stays at (125, 75).
      final anchored = TransformBoxLaw.scaled(
        stretched,
        bottomRight,
        CanvasPoint(x: 425, y: 175),
        aboutCentre: false,
        uniform: true,
      );
      expect(anchored.sx, closeTo(3, 1e-9));
      expect(anchored.sy, closeTo(2, 1e-9));
      final topLeft = anchored.apply(CanvasPoint(x: 150, y: 75));
      expect(topLeft.x, closeTo(125, 1e-9));
      expect(topLeft.y, closeTo(75, 1e-9));
    });

    // 🗣️F-265 (유저 2026-10-03): 「반전을 숫자로서 표현못하는게 원인인거
    // 같으니 구조적으로 해결」. A mirror is a minus on one scale, and the fit
    // projected the mirrored handle onto the UNmirrored diagonal: on a
    // square box that is zero. 🧪2026-10-06: one pixel of corner drag after
    // 좌우반전 left the picture at 1%.
    test('🚨…and a mirror: a corner of a flipped box neither un-flips it nor '
        'collapses it', () {
      final mirrored = SelectionAffine(
        pivot: CanvasPoint(x: 200, y: 100),
        sx: -1,
      );
      // The bottom-right handle is drawn at the bottom LEFT: (150, 125).
      final still = TransformBoxLaw.scaled(
        mirrored,
        bottomRight,
        CanvasPoint(x: 150, y: 125),
        aboutCentre: true,
        uniform: true,
      );
      expect(still.sx, closeTo(-1, 1e-9));
      expect(still.sy, closeTo(1, 1e-9));

      final grown = TransformBoxLaw.scaled(
        mirrored,
        bottomRight,
        CanvasPoint(x: 100, y: 150),
        aboutCentre: true,
        uniform: true,
      );
      expect(grown.sx, closeTo(-2, 1e-9));
      expect(grown.sy, closeTo(2, 1e-9));

      // Through the centre and out the other side: both axes change sign —
      // the mirror a drag past the anchor has always been.
      final through = TransformBoxLaw.scaled(
        mirrored,
        bottomRight,
        CanvasPoint(x: 250, y: 75),
        aboutCentre: true,
        uniform: true,
      );
      expect(through.sx, closeTo(1, 1e-9));
      expect(through.sy, closeTo(-1, 1e-9));
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
