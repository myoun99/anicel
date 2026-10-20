import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/input/pen_readings.dart';
import 'package:anicel/src/services/stroke_post_correction.dart';

PenPoint _at(double x, double y, {double pressure = 1}) => (
  position: CanvasPoint(x: x, y: y),
  readings: (pressure: pressure, lean: null, speed: 0.5),
);

/// A line along y = 20 from x = 0 to x = 100, wobbling ±[wobble] every
/// 5 px, its pressure rising from 0 to 1.
List<PenPoint> _wobbly(double wobble) => [
  for (var i = 0; i <= 20; i += 1)
    _at(
      i * 5.0,
      20 + (i == 0 || i == 20 ? 0 : (i.isEven ? wobble : -wobble)),
      pressure: i / 20,
    ),
];

/// Right along y = 0 to x = 60, then down to y = [down].
List<PenPoint> _corner({int down = 60}) => [
  for (var i = 0; i <= 12; i += 1) _at(i * 5.0, 0),
  for (var y = 5; y <= down; y += 5) _at(60, y.toDouble()),
];

void main() {
  for (final bezier in [false, true]) {
    group(bezier ? 'on a quadratic chain' : 'on a spline', () {
      test('a wobble within reach is taken out', () {
        final line = postCorrected(_wobbly(1.5), within: 2, bezier: bezier);
        for (final point in line) {
          expect(point.position.y, closeTo(20, 1e-9));
        }
      });

      test('a wobble beyond reach stays', () {
        final line = postCorrected(_wobbly(3), within: 2, bezier: bezier);
        final off = line.map((p) => (p.position.y - 20).abs());
        expect(off.reduce((a, b) => a > b ? a : b), greaterThan(1));
      });

      test('it leaves where the line left and arrives where it arrived', () {
        final drawn = _wobbly(1.5);
        final line = postCorrected(drawn, within: 2, bezier: bezier);
        expect(line.first, drawn.first);
        expect(line.last.position, drawn.last.position);
        expect(line.last.readings, drawn.last.readings);
      });

      test('it is laid in pieces no longer than two pixels, where it '
          'bulges past its chord too', () {
        // A corner with its legs uneven: the curve runs fastest along the
        // long one.
        for (final down in [60, 10]) {
          final line = postCorrected(
            _corner(down: down),
            within: 2,
            bezier: bezier,
          );
          for (var i = 1; i < line.length; i += 1) {
            expect(
              line[i - 1].position.distanceTo(line[i].position),
              lessThanOrEqualTo(2.0 + 1e-9),
              reason: 'down $down, piece $i',
            );
          }
        }
      });

      test('each point reads what the pen read as far along the line', () {
        // Samples a pixel apart for the first half and ten apart after,
        // the pen pressing x / 100: so far along the line, so hard — not so
        // many samples along it.
        final drawn = [
          for (var x = 0; x < 50; x += 1)
            _at(x.toDouble(), 20, pressure: x / 100),
          for (var x = 50; x <= 100; x += 10)
            _at(x.toDouble(), 20, pressure: x / 100),
        ];
        final line = postCorrected(drawn, within: 2, bezier: bezier);
        for (final point in line) {
          expect(
            point.readings.pressure,
            closeTo(point.position.x / 100, 0.01),
          );
        }
      });
    });
  }

  test('a spline goes through the corner, a quadratic chain cuts inside '
      'it', () {
    final corner = CanvasPoint(x: 60, y: 0);
    final spline = postCorrected(_corner(), within: 2, bezier: false);
    expect(spline.map((p) => p.position), contains(corner));

    final chain = postCorrected(_corner(), within: 2, bezier: true);
    final nearest = chain
        .map((p) => p.position.distanceTo(corner))
        .reduce((a, b) => a < b ? a : b);
    expect(nearest, greaterThan(5));
  });

  test('keeping its corners (角をとがらせる), either lays the line into the '
      'corner and out of it along its two sides (F-418-Q11)', () {
    final corner = CanvasPoint(x: 60, y: 0);
    double offTheSides(List<PenPoint> line) => line
        .map(
          (p) => [
            p.position.distanceToSegment(CanvasPoint(x: 0, y: 0), corner),
            p.position.distanceToSegment(corner, CanvasPoint(x: 60, y: 60)),
          ].reduce((a, b) => a < b ? a : b),
        )
        .reduce((a, b) => a > b ? a : b);
    for (final bezier in [false, true]) {
      final kept = postCorrected(
        _corner(),
        within: 2,
        bezier: bezier,
        keepCorners: true,
      );
      expect(kept.map((p) => p.position), contains(corner));
      expect(offTheSides(kept), lessThan(1e-9), reason: 'bezier $bezier');

      final rounded = postCorrected(_corner(), within: 2, bezier: bezier);
      expect(offTheSides(rounded), greaterThan(1), reason: 'bezier $bezier');
    }
  });

  test('nothing to take out, nothing changes', () {
    final drawn = _wobbly(1.5);
    expect(postCorrected(drawn, within: 0, bezier: true), same(drawn));
    final two = drawn.take(2).toList();
    expect(postCorrected(two, within: 2, bezier: false), same(two));
  });

  test('a lean is read the shorter way round', () {
    final between = readingsBetween(
      (pressure: 1, lean: (azimuthDegrees: 350, altitude: 0.5), speed: 0),
      (pressure: 1, lean: (azimuthDegrees: 10, altitude: 0.7), speed: 0),
      0.5,
    );
    expect(between.lean!.azimuthDegrees, closeTo(0, 1e-9));
    expect(between.lean!.altitude, closeTo(0.6, 1e-9));
  });
}
