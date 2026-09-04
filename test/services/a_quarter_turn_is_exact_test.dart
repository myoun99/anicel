import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/selection_affine.dart';

/// 🚨A QUARTER TURN IS EXACT, OR IT IS A ROUNDING ACCIDENT.
///
/// `math.cos(pi / 2)` is 6.1e-17, not zero, and that residue is enough to
/// make a quarter turn miss the resampler's lattice: destination pixel
/// centres land a hair off source pixel centres, the footprint reaches a
/// neighbour it should not, and "rotating by 90 degrees gives back the same
/// pixels" stops being a guarantee.
///
/// The outline ([apply]) and the pixels (the resample fold) both read
/// [SelectionAffine.cosTheta] and [SelectionAffine.sinTheta], so the ants
/// and the picture cannot disagree about where the rotation went — which is
/// exactly what a second copy of this table would let happen.
void main() {
  final pivot = CanvasPoint(x: 100, y: 50);

  SelectionAffine at({
    double sx = 1,
    double sy = 1,
    double rotationDegrees = 0,
    double tx = 0,
    double ty = 0,
  }) => SelectionAffine(
    pivot: pivot,
    sx: sx,
    sy: sy,
    rotationDegrees: rotationDegrees,
    tx: tx,
    ty: ty,
  );

  group('the quarter turns are exact', () {
    test('0, 90, 180 and 270 read the table, not the library', () {
      expect(at(rotationDegrees: 0).cosTheta, 1.0);
      expect(at(rotationDegrees: 0).sinTheta, 0.0);
      expect(at(rotationDegrees: 90).cosTheta, 0.0);
      expect(at(rotationDegrees: 90).sinTheta, 1.0);
      expect(at(rotationDegrees: 180).cosTheta, -1.0);
      expect(at(rotationDegrees: 180).sinTheta, 0.0);
      expect(at(rotationDegrees: 270).cosTheta, 0.0);
      expect(at(rotationDegrees: 270).sinTheta, -1.0);
    });

    test('a full turn past them is still exact', () {
      expect(at(rotationDegrees: 450).cosTheta, 0.0);
      expect(at(rotationDegrees: 450).sinTheta, 1.0);
      expect(at(rotationDegrees: 360).cosTheta, 1.0);
    });

    test('NEGATIVE quarter turns wrap into the table rather than off it', () {
      expect(at(rotationDegrees: -90).cosTheta, 0.0);
      expect(
        at(rotationDegrees: -90).sinTheta,
        -1.0,
        reason: 'a left-hand quarter turn is as exact as a right-hand one',
      );
      expect(at(rotationDegrees: -180).cosTheta, -1.0);
    });

    test('anything in between goes to the library', () {
      final tilted = at(rotationDegrees: 45);
      expect(tilted.cosTheta, closeTo(math.sqrt1_2, 1e-12));
      expect(tilted.sinTheta, closeTo(math.sqrt1_2, 1e-12));
    });
  });

  group('apply', () {
    test('identity leaves a point exactly where it was', () {
      final point = CanvasPoint(x: 7, y: 9);
      final moved = at().apply(point);
      expect(moved.x, point.x);
      expect(moved.y, point.y);
      expect(at().isIdentity, isTrue);
    });

    test('the PIVOT is the one point rotation and scale leave alone', () {
      final turned = at(rotationDegrees: 90, sx: 3, sy: 0.5).apply(pivot);
      expect(turned.x, pivot.x);
      expect(turned.y, pivot.y);
    });

    test('a translation moves the pivot too', () {
      final moved = at(tx: 5, ty: -4).apply(pivot);
      expect(moved.x, pivot.x + 5);
      expect(moved.y, pivot.y - 4);
    });

    test('a quarter turn lands on the axis EXACTLY, no residue', () {
      final turned = at(rotationDegrees: 90).apply(CanvasPoint(x: 110, y: 50));
      expect(
        turned.x,
        pivot.x,
        reason:
            'a point due right of the pivot turns to due below it — '
            'with a library cosine this is 100.000000000000006',
      );
      expect(turned.y, pivot.y + 10);
    });

    test('scale happens BEFORE rotation, about the pivot', () {
      // 10 to the right, scaled x3 = 30, then a quarter turn puts it below.
      final turned = at(
        sx: 3,
        rotationDegrees: 90,
      ).apply(CanvasPoint(x: 110, y: 50));
      expect(turned.x, pivot.x);
      expect(turned.y, pivot.y + 30);
    });
  });

  group('applyInverse', () {
    test('it undoes apply, whatever the composite', () {
      final affine = at(sx: 1.75, sy: 0.4, rotationDegrees: 37, tx: 12, ty: -8);
      final point = CanvasPoint(x: -13.5, y: 61.25);
      final back = affine.applyInverse(affine.apply(point));
      expect(back.x, closeTo(point.x, 1e-9));
      expect(back.y, closeTo(point.y, 1e-9));
    });

    test('a quarter turn round-trips exactly, not just closely', () {
      final affine = at(rotationDegrees: 270, tx: 3);
      final point = CanvasPoint(x: 40, y: 90);
      final back = affine.applyInverse(affine.apply(point));
      expect(back.x, point.x);
      expect(back.y, point.y);
    });
  });

  test('isIdentity ignores the pivot — it asks what the transform DOES', () {
    final elsewhere = SelectionAffine(pivot: CanvasPoint(x: -400, y: 900));
    expect(elsewhere.isIdentity, isTrue);
    expect(at(sx: 1.0001).isIdentity, isFalse);
    expect(at(ty: 0.0001).isIdentity, isFalse);
  });

  test('copyWith keeps the pivot — the session fixes it once and every '
      'later edit is about the same box', () {
    final next = at(sx: 2).copyWith(rotationDegrees: 15);
    expect(next.pivot, pivot);
    expect(next.sx, 2, reason: 'and it keeps what it was not asked to change');
    expect(next.rotationDegrees, 15);
  });
}
