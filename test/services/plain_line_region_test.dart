import 'dart:math' as math;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/plain_line_region.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape tool's 「일반」 line as the AREA it covers (I-69, 유저 답 Q8).
///
/// Every probe sits a tenth of a pixel to one side of an edge the law puts
/// somewhere exact, so an edge that moved shows which way it went.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  CanvasSelectionRegion line(
    List<CanvasPoint> points, {
    required double width,
    required ShapeCorners corners,
    bool closed = false,
  }) => plainLineRegion(
    points: points,
    closed: closed,
    width: width,
    corners: corners,
  )!;

  Matcher covers(double x, double y) => predicate<CanvasSelectionRegion>(
    (region) => region.containsPoint(p(x, y)),
    'covers ($x, $y)',
  );

  // 100 wide, 80 high.
  final box = [p(100, 100), p(200, 100), p(200, 180), p(100, 180)];

  group('a line', () {
    final ends = [p(100, 200), p(220, 200)];

    test('「각지게」 is the box round the segment: as wide as it is told, and '
        'cut square AT its two ends', () {
      final region = line(ends, width: 10, corners: ShapeCorners.sharp);

      expect(region, covers(160, 200), reason: 'along it');
      expect(region, covers(160, 195.1), reason: 'half the width one way');
      expect(region, covers(160, 204.9), reason: 'and the other');
      expect(region, isNot(covers(160, 194.9)), reason: 'and no wider');
      expect(region, isNot(covers(160, 205.1)));
      expect(region, covers(100.1, 204.9), reason: 'square to the very end');
      expect(region, covers(219.9, 195.1));
      expect(region, isNot(covers(99.9, 200)), reason: 'as long as traced');
      expect(region, isNot(covers(220.1, 200)));
    });

    test('「둥글게」 rounds both ends by half the width', () {
      final region = line(ends, width: 10, corners: ShapeCorners.round);

      expect(region, covers(95.2, 200), reason: 'past one end, by the half');
      expect(region, covers(224.8, 200), reason: 'and past the other');
      expect(region, isNot(covers(94.8, 200)), reason: 'and no further');
      expect(region, isNot(covers(225.2, 200)));
      expect(
        region,
        isNot(covers(96, 196)),
        reason: 'a round end has no corner of the square one',
      );
      expect(region, isNot(covers(224, 204)));
      expect(region, covers(160, 195.1), reason: 'the width is the same');
      expect(region, isNot(covers(160, 194.9)));
    });

    test('it need not lie along the grid', () {
      // (0,0) → (30,40): 50 long, and (0.8, -0.6) is a step across it.
      final region = line(
        [p(0, 0), p(30, 40)],
        width: 10,
        corners: ShapeCorners.sharp,
      );

      expect(region, covers(15 + 0.8 * 4.9, 20 - 0.6 * 4.9));
      expect(region, isNot(covers(15 + 0.8 * 5.1, 20 - 0.6 * 5.1)));
      expect(region, covers(15 - 0.8 * 4.9, 20 + 0.6 * 4.9));
      expect(region, isNot(covers(15 - 0.8 * 5.1, 20 + 0.6 * 5.1)));
      expect(
        region,
        isNot(covers(30 + 0.6 * 0.1, 40 + 0.8 * 0.1)),
        reason: 'cut square across ITS end, not across the grid',
      );
      expect(
        region,
        covers(30 - 0.6 * 0.1 + 0.8 * 4.8, 40 - 0.8 * 0.1 - 0.6 * 4.8),
        reason: 'and whole up to it',
      );
    });
  });

  group('a rectangle', () {
    test('「각지게」 is a ring of the one width — its corners are corners', () {
      final region = line(
        box,
        width: 10,
        corners: ShapeCorners.sharp,
        closed: true,
      );

      expect(region, covers(150, 95.1), reason: 'the top, outside the trace');
      expect(region, covers(150, 104.9), reason: 'and inside it');
      expect(region, isNot(covers(150, 94.9)));
      expect(region, isNot(covers(150, 105.1)), reason: 'the hole');
      expect(region, covers(204.9, 140), reason: 'the right');
      expect(region, isNot(covers(205.1, 140)));
      expect(region, covers(150, 184.9), reason: 'the bottom');
      expect(region, covers(95.1, 140), reason: 'the left');
      expect(region, isNot(covers(150, 140)), reason: 'nothing is filled in');

      expect(region, covers(95.1, 95.1), reason: 'the corner, to its point');
      expect(region, covers(204.9, 95.1));
      expect(region, covers(204.9, 184.9));
      expect(region, covers(95.1, 184.9));
      expect(region, isNot(covers(94.9, 94.9)), reason: 'and no further');
      expect(region, covers(104.9, 104.9), reason: 'square on the inside too');
      expect(region, isNot(covers(105.1, 105.1)));
    });

    test('「둥글게」 rounds the corners by half the width', () {
      final region = line(
        box,
        width: 10,
        corners: ShapeCorners.round,
        closed: true,
      );

      expect(
        region,
        isNot(covers(95.5, 95.5)),
        reason: 'the point of the corner is rounded away',
      );
      expect(region, isNot(covers(204.5, 184.5)));
      expect(region, covers(97, 97), reason: 'what is within the half stays');
      expect(region, covers(203, 183));
      expect(region, covers(150, 95.1), reason: 'the sides are as they were');
      expect(region, isNot(covers(150, 94.9)));
      expect(region, covers(104.9, 104.9));
      expect(region, isNot(covers(105.1, 105.1)));
      expect(region, isNot(covers(150, 140)));
    });

    test('covers the same whichever way round it was traced', () {
      for (final corners in ShapeCorners.values) {
        final one = line(box, width: 10, corners: corners, closed: true);
        final other = line(
          box.reversed.toList(),
          width: 10,
          corners: corners,
          closed: true,
        );
        for (var x = 90.25; x < 210; x += 2.5) {
          for (var y = 90.25; y < 190; y += 2.5) {
            expect(
              other.containsPoint(p(x, y)),
              one.containsPoint(p(x, y)),
              reason: '$corners at ($x, $y)',
            );
          }
        }
      }
    });

    test('a line wider than the shape covers its middle, with no hole left '
        'inside out', () {
      for (final corners in ShapeCorners.values) {
        final region = line(
          [p(100, 100), p(110, 100), p(110, 106), p(100, 106)],
          width: 30,
          corners: corners,
          closed: true,
        );

        expect(region, covers(105, 103), reason: '$corners: the middle');
        expect(region, covers(102, 104), reason: '$corners');
        expect(region, covers(86, 103), reason: '$corners: half out to a side');
        expect(region, isNot(covers(84, 103)), reason: '$corners');
      }
    });
  });

  group('an ellipse', () {
    // The outline the shape tool traces: 200 across, 100 high, round (400,
    // 150). Its points lie ON the ellipse and its sides sag inside it by
    // less than half a pixel, which is the slack these probes leave.
    final outline = CanvasSelectionShape.ellipse(
      left: 300,
      top: 100,
      right: 500,
      bottom: 200,
    ).points;

    test('is a ring of the one width all the way round', () {
      for (final corners in ShapeCorners.values) {
        final region = line(
          outline,
          width: 10,
          corners: corners,
          closed: true,
        );

        for (var degrees = 0; degrees < 360; degrees += 5) {
          final angle = degrees * math.pi / 180;
          // Out along the ellipse's own normal, which is where the width
          // is measured.
          final onIt = p(
            400 + 100 * math.cos(angle),
            150 + 50 * math.sin(angle),
          );
          final nx = math.cos(angle) / 100;
          final ny = math.sin(angle) / 50;
          final length = math.sqrt(nx * nx + ny * ny);
          CanvasPoint out(double by) =>
              p(onIt.x + nx / length * by, onIt.y + ny / length * by);

          final why = '$corners at $degrees°';
          expect(region.containsPoint(out(0)), isTrue, reason: why);
          expect(region.containsPoint(out(4)), isTrue, reason: why);
          expect(region.containsPoint(out(-4)), isTrue, reason: why);
          expect(region.containsPoint(out(5.6)), isFalse, reason: why);
          expect(region.containsPoint(out(-6.1)), isFalse, reason: why);
        }
        expect(region, isNot(covers(400, 150)), reason: '$corners: its middle');
      }
    });

    test('a flat one drawn with a fat line is filled across, tips and all — '
        'the outline pushed inwards would have knotted there', () {
      final flat = CanvasSelectionShape.ellipse(
        left: 0,
        top: 0,
        right: 200,
        bottom: 20,
      ).points;
      for (final corners in ShapeCorners.values) {
        final region = line(flat, width: 12, corners: corners, closed: true);

        // 12 wide leaves a slit 8 high at the middle and closes it about
        // 20 from either tip.
        expect(region, isNot(covers(100, 10)), reason: '$corners: the slit');
        for (var x = 1.5; x < 18; x += 1) {
          expect(region, covers(x, 10), reason: '$corners: no hole at $x');
          expect(region, covers(200 - x, 10), reason: '$corners');
        }
      }
    });
  });

  group('a corner too sharp to be carried to its point is cut across', () {
    // Two sides 100 long meeting at (100, 0), [between] degrees apart.
    CanvasSelectionRegion corner(double between) {
      final angle = between * math.pi / 180;
      return line(
        [
          p(0, 0),
          p(100, 0),
          p(100 - 100 * math.cos(angle), 100 * math.sin(angle)),
        ],
        width: 10,
        corners: ShapeCorners.sharp,
      );
    }

    // Where the two outer edges meet: `half / sin(between / 2)` from the
    // corner, out along the line that halves the angle.
    double pointOf(double between) {
      final half = between * math.pi / 360;
      return 100 + 5 / math.sin(half) * math.cos(half);
    }

    test('a right angle and a 60° one reach their points', () {
      expect(corner(90).coverageBounds.right, closeTo(pointOf(90), 1e-9));
      expect(pointOf(90), closeTo(105, 1e-9));
      expect(corner(60).coverageBounds.right, closeTo(pointOf(60), 1e-9));
      expect(corner(60), covers(pointOf(60) - 0.2, -4.95));
    });

    test('🚨the limit is four widths of corner: 30° reaches its point, 28° '
        'is cut — and the area stops where the line does', () {
      // 1 / sin(15°) = 3.86 widths, 1 / sin(14°) = 4.13.
      expect(corner(30).coverageBounds.right, closeTo(pointOf(30), 1e-9));

      // The second side leaves (100, 0) along (-0.883, 0.469); its outer
      // edge starts at (102.35, 4.41), and the first side's ends at
      // (100, -5).
      final cut = corner(28);
      expect(pointOf(28), greaterThan(119));
      expect(cut.coverageBounds.right, lessThan(103));
      expect(cut, covers(99.9, -4.9), reason: 'the sides are whole');
      expect(cut, covers(99.46, 5.38));
      expect(
        cut,
        covers(101, -0.25),
        reason: 'and it is closed straight across, from one outer edge to '
            'the other',
      );
      expect(
        cut,
        isNot(covers(101.6, -0.6)),
        reason: 'with nothing beyond that on the way to the point',
      );
    });

    test('a path that doubles straight back has no corner at all', () {
      final region = line(
        [p(0, 0), p(100, 0), p(0, 0)],
        width: 10,
        corners: ShapeCorners.sharp,
      );

      expect(region.coverageBounds.right, 100);
      expect(region, covers(99.9, 4.9));
      expect(region, isNot(covers(100.1, 0)));
    });
  });

  group('nothing to cover', () {
    test('no width, no area', () {
      for (final corners in ShapeCorners.values) {
        expect(
          plainLineRegion(
            points: box,
            closed: true,
            width: 0,
            corners: corners,
          ),
          isNull,
        );
      }
    });

    test('a path that goes nowhere has none either', () {
      for (final corners in ShapeCorners.values) {
        for (final closed in [true, false]) {
          expect(
            plainLineRegion(
              points: [p(5, 5), p(5, 5), p(5, 5)],
              closed: closed,
              width: 10,
              corners: corners,
            ),
            isNull,
            reason: '$corners, closed: $closed',
          );
          expect(
            plainLineRegion(
              points: const [],
              closed: closed,
              width: 10,
              corners: corners,
            ),
            isNull,
          );
        }
      }
    });

    test('a point said twice is one point: no side of no length', () {
      final region = line(
        [p(100, 200), p(100, 200), p(220, 200), p(220, 200)],
        width: 10,
        corners: ShapeCorners.sharp,
      );

      expect(region, covers(160, 204.9));
      expect(region, isNot(covers(160, 205.1)));
      expect(region, isNot(covers(220.1, 200)));
    });

    test('an outline squeezed flat is the segment it is squeezed to', () {
      // A rectangle dragged out with no height: there and back.
      final flat = [p(100, 200), p(220, 200), p(220, 200), p(100, 200)];

      final sharp = line(
        flat,
        width: 10,
        corners: ShapeCorners.sharp,
        closed: true,
      );
      expect(sharp, covers(160, 204.9));
      expect(sharp, covers(100.1, 195.1));
      expect(sharp, isNot(covers(99.9, 200)));
      expect(sharp, isNot(covers(220.1, 200)));

      final round = line(
        flat,
        width: 10,
        corners: ShapeCorners.round,
        closed: true,
      );
      expect(round, covers(224.8, 200));
      expect(round, covers(95.2, 200));
      expect(round, isNot(covers(225.2, 200)));
    });
  });
}
