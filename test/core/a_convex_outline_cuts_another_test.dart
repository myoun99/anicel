import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/convex_clip.dart';

/// What a conte picture takes of the paper is its rounded slot, where the
/// camera's frame is, where the canvas is — three convex outlines cut down
/// to one, and a press asked whether it lies in it.
void main() {
  const square = [Offset.zero, Offset(10, 0), Offset(10, 10), Offset(0, 10)];

  double area(List<Offset> polygon) {
    var sum = 0.0;
    for (var index = 0; index < polygon.length; index += 1) {
      final a = polygon[index];
      final b = polygon[(index + 1) % polygon.length];
      sum += a.dx * b.dy - a.dy * b.dx;
    }
    return sum.abs() / 2;
  }

  test('two squares overlapping by a quarter meet in that quarter', () {
    final met = convexIntersection(square, const [
      Offset(5, 5),
      Offset(15, 5),
      Offset(15, 15),
      Offset(5, 15),
    ]);

    expect(area(met), closeTo(25, 1e-9));
    for (final corner in met) {
      expect(corner.dx, inInclusiveRange(5, 10));
      expect(corner.dy, inInclusiveRange(5, 10));
    }
  });

  test('either way round — a clip wound the other way cuts the same', () {
    final clockwise = convexIntersection(square, const [
      Offset(5, 5),
      Offset(15, 5),
      Offset(15, 15),
      Offset(5, 15),
    ]);
    final counter = convexIntersection(square, const [
      Offset(5, 15),
      Offset(15, 15),
      Offset(15, 5),
      Offset(5, 5),
    ]);

    expect(area(counter), closeTo(area(clockwise), 1e-9));
  });

  test('a turned square cuts the corners off', () {
    // |x − 5| + |y − 5| ≤ 8: each corner loses a triangle of legs 2.
    final met = convexIntersection(square, const [
      Offset(5, -3),
      Offset(13, 5),
      Offset(5, 13),
      Offset(-3, 5),
    ]);

    expect(area(met), closeTo(100 - 4 * 2, 1e-9));
    expect(convexContains(met, const Offset(0.5, 0.5)), isFalse);
    expect(convexContains(met, const Offset(5, 5)), isTrue);
  });

  test('what does not meet is nothing; what lies inside is itself', () {
    expect(
      convexIntersection(square, const [
        Offset(20, 20),
        Offset(30, 20),
        Offset(30, 30),
      ]),
      isEmpty,
    );
    const inner = [Offset(2, 2), Offset(8, 2), Offset(8, 8), Offset(2, 8)];
    expect(area(convexIntersection(inner, square)), closeTo(36, 1e-9));
  });

  test('a point is in an outline on its edges, and not outside them', () {
    expect(convexContains(square, const Offset(5, 5)), isTrue);
    expect(convexContains(square, const Offset(10, 5)), isTrue);
    expect(convexContains(square, const Offset(10.01, 5)), isFalse);
    expect(
      convexContains(const [Offset.zero, Offset(1, 1)], Offset.zero),
      isFalse,
      reason: 'two points hold nothing',
    );
  });
}
