import 'dart:math' as math;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/services/shape_ratio_lock.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape tool's 「비율 고정」 (유저 답 I-69-Q5): 정사각형 · 정원 · 45°
/// 직선.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  CanvasPoint kept(
    CanvasShapeKind shape,
    CanvasPoint to, {
    CanvasPoint? from,
  }) => ratioKeptEnd(from: from ?? p(0, 0), to: to, shape: shape);

  void expectAt(CanvasPoint point, double x, double y) {
    expect(point.x, x);
    expect(point.y, y);
  }

  group('a box is a square', () {
    for (final shape in [CanvasShapeKind.rect, CanvasShapeKind.ellipse]) {
      test('$shape: its side is the longer way the hand has gone, towards '
          'the hand both ways', () {
        expectAt(kept(shape, p(30, 10)), 30, 30);
        expectAt(kept(shape, p(10, 30)), 30, 30);
        expectAt(kept(shape, p(-30, 10)), -30, 30);
        expectAt(kept(shape, p(10, -30)), 30, -30);
        expectAt(kept(shape, p(-10, -30)), -30, -30);
      });

      test('$shape: from wherever it was pressed', () {
        expectAt(kept(shape, p(130, 60), from: p(100, 50)), 130, 80);
        expectAt(kept(shape, p(95, 20), from: p(100, 50)), 70, 20);
      });

      test('$shape: a drag straight along one way is still a square', () {
        expectAt(kept(shape, p(0, 20)), 20, 20);
        expectAt(kept(shape, p(-20, 0)), -20, 20);
        expectAt(kept(shape, p(0, 0)), 0, 0);
      });
    }
  });

  group('a line goes one of eight ways', () {
    const line = CanvasShapeKind.line;

    test('level and upright are EXACT: no rise in one, no run in the '
        'other', () {
      expectAt(kept(line, p(100, 5)), 100, 0);
      expectAt(kept(line, p(-100, -3)), -100, 0);
      expectAt(kept(line, p(4, 100)), 0, 100);
      expectAt(kept(line, p(3, -100)), 0, -100);
    });

    test('a diagonal\'s run and rise are one number, and it ends at the '
        'point of its way nearest the hand', () {
      for (final (to, sx, sy) in [
        (p(100, 90), 1, 1),
        (p(-100, 90), -1, 1),
        (p(-100, -90), -1, -1),
        (p(100, -90), 1, -1),
      ]) {
        final end = kept(line, to);
        expect(end.x * sx, end.y * sy, reason: 'at 45°, exactly');
        expect(end.x * sx, closeTo(95, 1e-9), reason: 'half of 100 + 90');
      }
    });

    test('the nearest way wins: 22.5° is where level gives way to the '
        'diagonal', () {
      CanvasPoint at(double degrees) => p(
        100 * math.cos(degrees * math.pi / 180),
        100 * math.sin(degrees * math.pi / 180),
      );

      expect(kept(line, at(22)).y, 0, reason: 'still level');
      expect(kept(line, at(23)).y, greaterThan(60), reason: 'the diagonal');
      expect(kept(line, at(67)).x, greaterThan(60));
      expect(kept(line, at(68)).x, 0, reason: 'upright');
      expect(kept(line, at(-22)).y, 0);
      expect(kept(line, at(-23)).y, lessThan(-60));
      expect(kept(line, at(158)).y, 0);
      expect(kept(line, at(157)).y, greaterThan(60));
    });

    test('from wherever it was pressed', () {
      expectAt(kept(line, p(220, 230), from: p(100, 200)), 220, 200);
    });
  });

  test('a shape that is the hand\'s own path has no ratio to keep', () {
    for (final shape in [CanvasShapeKind.lasso, CanvasShapeKind.polygon]) {
      final to = p(37, -12);
      expect(kept(shape, to), same(to));
    }
  });
}
