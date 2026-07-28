import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';

void main() {
  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF000000,
    size: 4,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  group('CanvasSelectionShape', () {
    test('rect contains its interior, not its outside', () {
      final shape = CanvasSelectionShape.rect(
        left: 40,
        top: 10,
        right: 10,
        bottom: 30,
      );
      expect(shape.containsPoint(CanvasPoint(x: 20, y: 20)), isTrue);
      expect(shape.containsPoint(CanvasPoint(x: 5, y: 20)), isFalse);
      expect(shape.containsPoint(CanvasPoint(x: 20, y: 35)), isFalse);
    });

    test('a concave lasso polygon selects by even-odd containment', () {
      // A "U" shape: the notch between the arms is OUTSIDE.
      final shape = CanvasSelectionShape([
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: 30, y: 0),
        CanvasPoint(x: 30, y: 30),
        CanvasPoint(x: 20, y: 30),
        CanvasPoint(x: 20, y: 10),
        CanvasPoint(x: 10, y: 10),
        CanvasPoint(x: 10, y: 30),
        CanvasPoint(x: 0, y: 30),
      ]);
      expect(shape.containsPoint(CanvasPoint(x: 5, y: 20)), isTrue);
      expect(shape.containsPoint(CanvasPoint(x: 25, y: 20)), isTrue);
      expect(
        shape.containsPoint(CanvasPoint(x: 15, y: 20)),
        isFalse,
        reason: 'the notch is outside the U',
      );
    });

    test('translated moves every vertex', () {
      final shape = CanvasSelectionShape.rect(
        left: 0,
        top: 0,
        right: 10,
        bottom: 10,
      ).translated(dx: 5, dy: -2);
      expect(shape.containsPoint(CanvasPoint(x: 14, y: 7)), isTrue);
      expect(shape.containsPoint(CanvasPoint(x: 2, y: 2)), isFalse);
    });
  });

  group('SelectionAffine (P9b)', () {
    final pivot = CanvasPoint(x: 10, y: 10);

    test('identity maps points to themselves', () {
      final affine = SelectionAffine(pivot: pivot);
      expect(affine.isIdentity, isTrue);
      final mapped = affine.apply(CanvasPoint(x: 3, y: 7));
      expect(mapped.x, closeTo(3, 1e-9));
      expect(mapped.y, closeTo(7, 1e-9));
    });

    test('scales about the pivot, then translates', () {
      final affine = SelectionAffine(pivot: pivot, sx: 2, sy: 3, tx: 1, ty: -1);
      final mapped = affine.apply(CanvasPoint(x: 12, y: 11));
      // local (2,1) → scaled (4,3) → +pivot+t = (15, 12).
      expect(mapped.x, closeTo(15, 1e-9));
      expect(mapped.y, closeTo(12, 1e-9));
      // The pivot itself only translates.
      final center = affine.apply(pivot);
      expect(center.x, closeTo(11, 1e-9));
      expect(center.y, closeTo(9, 1e-9));
    });

    test('rotates 90° clockwise (y-down) about the pivot', () {
      final affine = SelectionAffine(pivot: pivot, rotationDegrees: 90);
      final mapped = affine.apply(CanvasPoint(x: 15, y: 10));
      // local (5,0) → (0,5) → canvas (10,15).
      expect(mapped.x, closeTo(10, 1e-9));
      expect(mapped.y, closeTo(15, 1e-9));
    });

    test('transformDabs maps centers, scales size by √|sx·sy|, turns the '
        'tip angle', () {
      final affine = SelectionAffine(
        pivot: pivot,
        sx: 2,
        sy: 8,
        rotationDegrees: 30,
      );
      final original = dab(12, 10).copyWith(angleDegrees: 5, size: 10);
      final mapped = transformDabs([original], affine).single;
      expect(mapped.size, closeTo(40, 1e-9)); // 10 · √16
      expect(mapped.angleDegrees, closeTo(35, 1e-9));
      expect(mapped.center.x, isNot(original.center.x));
    });

    test('transformShape maps every vertex', () {
      final shape = CanvasSelectionShape.rect(
        left: 0,
        top: 0,
        right: 20,
        bottom: 20,
      );
      final doubled = transformShape(
        shape,
        SelectionAffine(pivot: pivot, sx: 2, sy: 2),
      );
      // (0,0) local (−10,−10) → (−20,−20) → (−10,−10).
      expect(doubled.points.first.x, closeTo(-10, 1e-9));
      expect(doubled.points.first.y, closeTo(-10, 1e-9));
      expect(doubled.containsPoint(CanvasPoint(x: 25, y: 25)), isTrue);
    });
  });
}
