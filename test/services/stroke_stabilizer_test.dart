import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/stroke_stabilizer.dart';

void main() {
  test('the brush stays put while the pen is inside the rope', () {
    final stabilizer = StrokeStabilizer(
      ropeLength: 10,
      start: CanvasPoint(x: 0, y: 0),
    );
    final brush = stabilizer.follow(CanvasPoint(x: 6, y: 8)); // distance 10
    expect(brush.x, 0);
    expect(brush.y, 0);
  });

  test('a taut rope drags the brush along the pen direction, keeping '
      'exactly the rope length behind', () {
    final stabilizer = StrokeStabilizer(
      ropeLength: 10,
      start: CanvasPoint(x: 0, y: 0),
    );
    final brush = stabilizer.follow(CanvasPoint(x: 30, y: 0));
    expect(brush.x, closeTo(20, 1e-9));
    expect(brush.y, 0);

    // Sideways pull: the brush follows the straight line to the pen.
    final next = stabilizer.follow(CanvasPoint(x: 30, y: 30));
    final dx = 30 - next.x;
    final dy = 30 - next.y;
    expect(dx * dx + dy * dy, closeTo(100, 1e-6), reason: 'rope stays taut');
  });

  test('jitter smaller than the rope never moves the brush (the whole '
      'point of the stabilizer)', () {
    final stabilizer = StrokeStabilizer(
      ropeLength: 15,
      start: CanvasPoint(x: 50, y: 50),
    );
    for (final wiggle in [
      CanvasPoint(x: 55, y: 45),
      CanvasPoint(x: 47, y: 58),
      CanvasPoint(x: 52, y: 51),
    ]) {
      final brush = stabilizer.follow(wiggle);
      expect(brush.x, 50);
      expect(brush.y, 50);
    }
  });
}
