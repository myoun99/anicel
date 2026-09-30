import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// 🚨I-23 — 선택 반전: 「선택반전기능. 내용은 선택되지 않은 부분을 선택함」
/// (유저 2026-09-12), out to the pasteboard wall (I-23-Q1 「페이스트보드
/// 벽까지」).
///
/// The inverse is 「the wall, minus the selection」 with the selection held
/// as ONE operand, so these pin it against the selection's own pixels —
/// the complement, 255 − mask, at every pixel of the wall and nothing past
/// it — for every kind of fold a selection can be.
void main() {
  /// A small canvas, so its 3×3 wall is a box a test can read whole.
  const canvas = CanvasSize(width: 20, height: 15);
  final wall = canvas.pasteboardRect;

  /// The ring the pins read: the wall, and six pixels past every side.
  final ringLeft = wall.left.toInt() - 6;
  final ringTop = wall.top.toInt() - 6;
  final ringWidth = wall.width.toInt() + 12;
  final ringHeight = wall.height.toInt() + 12;

  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);

  CanvasSelectionShape rect(double l, double t, double r, double b) =>
      CanvasSelectionShape.rect(left: l, top: t, right: r, bottom: b);

  bool insideWall(int x, int y) =>
      x >= wall.left && x < wall.right && y >= wall.top && y < wall.bottom;

  Uint8List ringMask(CanvasSelectionRegion region) => region.maskFor(
    left: ringLeft,
    top: ringTop,
    width: ringWidth,
    height: ringHeight,
  );

  /// [original]'s inverse selects every pixel of the wall [original] does
  /// not and nothing past the wall, and its hit test agrees at each one.
  CanvasSelectionRegion expectInverse(CanvasSelectionRegion? original) {
    final inverse = CanvasSelectionRegion.invertedWithin(original, wall);
    expect(inverse, isNotNull, reason: 'the premise: something is left');
    final before = original == null ? null : ringMask(original);
    final after = ringMask(inverse!);
    var selectedBefore = 0;
    for (var row = 0; row < ringHeight; row += 1) {
      for (var column = 0; column < ringWidth; column += 1) {
        final x = ringLeft + column;
        final y = ringTop + row;
        final index = row * ringWidth + column;
        final wasSelected = before != null && before[index] != 0;
        if (wasSelected && insideWall(x, y)) {
          selectedBefore += 1;
        }
        final want = insideWall(x, y) && !wasSelected;
        expect(after[index], want ? 255 : 0, reason: 'mask at ($x, $y)');
        expect(
          inverse.containsPoint(at(x + 0.5, y + 0.5)),
          want,
          reason: 'containsPoint at ($x, $y)',
        );
      }
    }
    if (original != null) {
      expect(selectedBefore, greaterThan(0), reason: 'the premise');
    }
    return inverse;
  }

  // ⚠️Off-grid points: a pixel centre lying exactly on an edge is decided
  // by rounding, which says nothing about the inverse.
  CanvasSelectionRegion selfCrossingLasso() => CanvasSelectionRegion.shape(
    CanvasSelectionShape([
      at(-12.3, -8.6),
      at(21.7, 14.2),
      at(21.4, -9.1),
      at(-11.8, 16.3),
    ]),
  );

  group('the inverse is the complement inside the wall', () {
    test('of a rectangle', () {
      expectInverse(CanvasSelectionRegion.shape(rect(2.3, 1.7, 14.6, 9.2)));
    });

    test('of an ellipse', () {
      expectInverse(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.ellipse(
            left: -5.5,
            top: -3.2,
            right: 17.3,
            bottom: 12.8,
          ),
        ),
      );
    });

    test('of a lasso that crosses itself', () {
      expectInverse(selfCrossingLasso());
    });

    test('of a guide\'s overlapping copies', () {
      expectInverse(
        CanvasSelectionRegion.combineCopies(
          null,
          [rect(0, 0, 10, 10), rect(6, 2, 16, 12)],
          SelectionCombineMode.replace,
        ),
      );
    });

    test('of an add → subtract → add chain', () {
      final chain = CanvasSelectionRegion.shape(rect(-10, -8, 20, 20))
          .combinedWith(rect(-4, -2, 12, 12), SelectionCombineMode.subtract)!
          .combinedWith(rect(0, 2, 6, 8), SelectionCombineMode.add)!;

      expectInverse(chain);
    });

    test('of a 선택중 — the step a step-by-step inverse cannot undo', () {
      // A ∖ (B ∩ C) is not A ∖ B ∖ C: subtracting the two polygons one
      // after another would take away all of B and all of C.
      final narrowed = CanvasSelectionRegion.shape(
        rect(-8, -6, 18, 14),
      ).combinedWith(rect(4, 4, 30, 25), SelectionCombineMode.intersect)!;

      expectInverse(narrowed);
    });

    test('of an inverse', () {
      final inverse = CanvasSelectionRegion.invertedWithin(
        CanvasSelectionRegion.shape(rect(3, 3, 9, 9)),
        wall,
      );

      expectInverse(inverse);
    });
  });

  test('inverting twice gives the same pixels back', () {
    for (final original in [
      CanvasSelectionRegion.shape(rect(2.3, 1.7, 14.6, 9.2)),
      selfCrossingLasso(),
      CanvasSelectionRegion.shape(
        rect(-8, -6, 18, 14),
      ).combinedWith(rect(4, 4, 30, 25), SelectionCombineMode.intersect)!,
    ]) {
      final twice = CanvasSelectionRegion.invertedWithin(
        CanvasSelectionRegion.invertedWithin(original, wall),
        wall,
      );

      expect(ringMask(twice!), ringMask(original), reason: '$original');
    }
  });

  group('the two ends', () {
    test('nothing selected inverts to the whole wall', () {
      final inverse = expectInverse(null);

      expect(
        inverse,
        CanvasSelectionRegion.shape(
          rect(wall.left, wall.top, wall.right, wall.bottom),
        ),
      );
    });

    test('everything selected inverts to NO selection — so two presses '
        'come back', () {
      final everything = CanvasSelectionRegion.invertedWithin(null, wall);

      expect(CanvasSelectionRegion.invertedWithin(everything, wall), isNull);
    });
  });

  group('the nested operand answers every reader', () {
    CanvasSelectionRegion hole() =>
        CanvasSelectionRegion.shape(rect(2, 3, 12, 9));
    CanvasSelectionRegion inverseOfHole() =>
        CanvasSelectionRegion.invertedWithin(hole(), wall)!;

    test('coverage is the wall — what a lift has to allocate', () {
      final box = inverseOfHole().coverageBounds;

      expect(
        (box.left, box.top, box.right, box.bottom),
        (wall.left, wall.top, wall.right, wall.bottom),
      );
    });

    test('the selected box is tight: a band along the wall taken away '
        'pulls it in', () {
      final band = CanvasSelectionRegion.shape(
        rect(wall.left, wall.top, wall.right, 5),
      );
      final box = CanvasSelectionRegion.invertedWithin(
        band,
        wall,
      )!.selectedBounds;

      expect(box.top, 5, reason: 'the band is not selected');
      expect(box.left, wall.left);
      expect(box.right, wall.right);
      expect(box.bottom, wall.bottom);
    });

    test('the path says what the fold says', () {
      final inverse = inverseOfHole();
      final path = inverse.pathIn((point) => ui.Offset(point.x, point.y));

      expect(inverse.containsPoint(at(7.5, 6.5)), isFalse, reason: 'hole');
      expect(inverse.containsPoint(at(-15.5, -10.5)), isTrue, reason: 'wall');
      for (final (x, y) in [
        (7.5, 6.5),
        (-15.5, -10.5),
        (35.5, 25.5),
        (-25.5, 0.5),
        (45.5, 5.5),
      ]) {
        expect(
          path.contains(ui.Offset(x, y)),
          inverse.containsPoint(at(x, y)),
          reason: '($x, $y)',
        );
      }
    });

    test('a carried inverse carries its hole', () {
      final moved = inverseOfHole().translated(dx: 3, dy: -2);

      expect(moved.steps.last, isA<CanvasSelectionNested>());
      expect(moved.containsPoint(at(10.5, 4.5)), isFalse, reason: 'moved');
      expect(moved.containsPoint(at(3.5, 7.5)), isTrue, reason: 'left');
    });

    test('two inverses of one selection are one value', () {
      final a = inverseOfHole();
      final b = inverseOfHole();

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a ==
            CanvasSelectionRegion.invertedWithin(
              CanvasSelectionRegion.shape(rect(2, 3, 12, 10)),
              wall,
            ),
        isFalse,
      );
      expect(
        CanvasSelectionStep.region(hole(), SelectionCombineMode.subtract) ==
            CanvasSelectionStep(
              rect(2, 3, 12, 9),
              SelectionCombineMode.subtract,
            ),
        isFalse,
        reason: 'a nested selection is not the polygon it holds',
      );
      expect(
        CanvasSelectionRegion([
          CanvasSelectionStep.region(hole(), SelectionCombineMode.replace),
        ]).singleShape,
        isNull,
      );
    });

    test('mayCover answers from the wall', () {
      final inverse = inverseOfHole();

      expect(
        inverse.mayCover(
          DirtyRegion(left: 4, top: 4, rightExclusive: 6, bottomExclusive: 6),
        ),
        isTrue,
        reason: 'a superset: the hole is inside the box',
      );
      expect(
        inverse.mayCover(
          DirtyRegion(
            left: 60,
            top: 0,
            rightExclusive: 70,
            bottomExclusive: 10,
          ),
        ),
        isFalse,
        reason: 'past the wall',
      );
    });

    test('a nested selection that shrinks ITSELF keeps the box tight, '
        'even folded in by 추가', () {
      // Its coverage is the whole 30-wide rectangle; what it selects is
      // the left third. 추가 alone never shrinks, so only the operand can
      // say this box is only a superset.
      final leftThird = CanvasSelectionRegion.shape(
        rect(0, 0, 30, 20),
      ).combinedWith(rect(10, -1, 31, 21), SelectionCombineMode.subtract)!;
      final region = CanvasSelectionRegion([
        CanvasSelectionStep(rect(0, 0, 2, 2), SelectionCombineMode.replace),
        CanvasSelectionStep.region(leftThird, SelectionCombineMode.add),
      ]);

      expect(region.coverageBounds.right, 30, reason: 'the premise');
      expect(region.selectedBounds.right, 10);
    });
  });
}
