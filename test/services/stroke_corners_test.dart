import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/input/pen_readings.dart';
import 'package:anicel/src/services/stroke_corners.dart';

/// 角をとがらせる (F-418-Q11): which points of a line are its corners.
void main() {
  test('a straight line has none', () {
    expect(_cornersOf([_p(0, 0), _p(100, 0)]), isEmpty);
  });

  test("a square's are where it turns — not where it starts or ends", () {
    expect(
      _cornersOf([_p(0, 0), _p(40, 0), _p(40, 40), _p(0, 40), _p(0, 0)]),
      [_p(40, 0), _p(40, 40), _p(0, 40)],
    );
  });

  test('a V comes to its point, and so does a fold that comes straight '
      'back', () {
    expect(_cornersOf([_p(0, 0), _p(20, 40), _p(40, 0)]), [_p(20, 40)]);
    expect(_cornersOf([_p(0, 0), _p(40, 0), _p(10, 0)]), [_p(40, 0)]);
  });

  test('a turn of 70° is one, a turn of 60° is not', () {
    CanvasPoint after(double degrees) => _p(
      40 + 40 * math.cos(degrees * math.pi / 180),
      40 * math.sin(degrees * math.pi / 180),
    );
    expect(_cornersOf([_p(0, 0), _p(40, 0), after(71)]), [_p(40, 0)]);
    expect(_cornersOf([_p(0, 0), _p(40, 0), after(60)]), isEmpty);
  });

  test('a pen that rests where it starts or where it ends turns nowhere', () {
    final line = _along([_p(0, 0), _p(40, 0)]);
    expect(
      StrokeCorners.of([line.first, line.first, ...line, line.last]),
      isEmpty,
    );
  });

  test("a hand's wobble is none, nor a round curve", () {
    expect(
      _cornersOf([
        for (var i = 0; i <= 30; i += 1) _p(i * 3.0, i.isEven ? 1 : -1),
      ]),
      isEmpty,
    );
    expect(
      _cornersOf([
        for (var i = 0; i <= 36; i += 1)
          _p(30 * math.cos(i * math.pi / 18), 30 * math.sin(i * math.pi / 18)),
      ]),
      isEmpty,
    );
  });

  test('a corner is known once the line is past its turn, and the end '
      'gives the one it was still turning', () {
    final corners = StrokeCorners();
    final line = _along([_p(0, 0), _p(40, 0), _p(40, 40)]);
    final known = <(int, CanvasPoint)>[];
    for (final point in line) {
      for (final (:at, point: corner) in corners.add(point)) {
        known.add((at, corner.position));
        expect(
          point.position.distanceTo(corner.position),
          greaterThanOrEqualTo(8),
          reason: 'not before the line went on past it',
        );
      }
    }
    expect(known, [(40, _p(40, 0))]);

    final turning = StrokeCorners();
    for (final point in _along([_p(0, 0), _p(40, 0), _p(40, 8)])) {
      expect(turning.add(point), isEmpty);
    }
    expect(turning.end().map((corner) => corner.point.position), [_p(40, 0)]);
    expect(turning.end(), isEmpty, reason: 'given once');
  });
}

CanvasPoint _p(double x, double y) => CanvasPoint(x: x, y: y);

/// [vertices] joined, a point every pixel.
List<PenPoint> _along(List<CanvasPoint> vertices) => [
  (position: vertices.first, readings: _reads),
  for (var v = 1; v < vertices.length; v += 1)
    for (
      var step = 1;
      step <= vertices[v - 1].distanceTo(vertices[v]).ceil();
      step += 1
    )
      (
        position: CanvasPoint.lerp(
          vertices[v - 1],
          vertices[v],
          math.min(1.0, step / vertices[v - 1].distanceTo(vertices[v])),
        ),
        readings: _reads,
      ),
];

List<CanvasPoint> _cornersOf(List<CanvasPoint> vertices) {
  final line = _along(vertices);
  return [for (final at in StrokeCorners.of(line)) line[at].position];
}

const PenReadings _reads = (pressure: 1.0, lean: null, speed: 0.0);
