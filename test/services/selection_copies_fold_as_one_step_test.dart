import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// **The copies a symmetry guide makes are ONE step, folded as their union.**
///
/// The guide feature shipped with strokes covered and two holes written
/// down; this is the selection half of closing them.
///
/// 🚨Why a step holds a LIST rather than the copies becoming several steps:
/// folding them one after another gives the right answer for 갱신/추가/삭제
/// and the wrong one for 선택중. Narrowing to the left copy and then to the
/// right one keeps their overlap, which for a plain left/right mirror is
/// nothing at all — the user would drag a box and watch the whole selection
/// vanish. The step list is linear and cannot nest, so "∩ (A ∪ B)" has to be
/// one step or it cannot be said.
void main() {
  CanvasSelectionShape rect(double l, double t, double r, double b) =>
      CanvasSelectionShape.rect(left: l, top: t, right: r, bottom: b);

  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);

  bool maskSays(CanvasSelectionRegion region, int x, int y) =>
      region.maskFor(left: x, top: y, width: 1, height: 1)[0] != 0;

  void expectBoth(CanvasSelectionRegion region, int x, int y, bool inside) {
    expect(
      region.containsPoint(at(x + 0.5, y + 0.5)),
      inside,
      reason: 'containsPoint($x, $y)',
    );
    expect(maskSays(region, x, y), inside, reason: 'mask($x, $y)');
  }

  /// Two lobes with a gap between them — a left/right mirror's copies.
  final left = rect(0, 0, 6, 10);
  final right = rect(20, 0, 26, 10);

  group('one step, every mode', () {
    test('갱신 replaces with the union of the copies, not with the last', () {
      final region = CanvasSelectionRegion.combineCopies(
        CanvasSelectionRegion.shape(rect(40, 40, 50, 50)),
        [left, right],
        SelectionCombineMode.replace,
      )!;

      expectBoth(region, 3, 5, true);
      expectBoth(region, 23, 5, true);
      expectBoth(region, 13, 5, false);
      expectBoth(region, 45, 45, false);
      expect(region.steps, hasLength(1), reason: 'one act, one undo step');
    });

    test('추가 unions every copy in', () {
      final region = CanvasSelectionRegion.combineCopies(
        CanvasSelectionRegion.shape(rect(40, 0, 50, 10)),
        [left, right],
        SelectionCombineMode.add,
      )!;

      expectBoth(region, 3, 5, true);
      expectBoth(region, 23, 5, true);
      expectBoth(region, 45, 5, true);
      expectBoth(region, 13, 5, false);
    });

    test('삭제 cuts every copy out', () {
      final region = CanvasSelectionRegion.combineCopies(
        CanvasSelectionRegion.shape(rect(0, 0, 30, 10)),
        [left, right],
        SelectionCombineMode.subtract,
      )!;

      expectBoth(region, 3, 5, false);
      expectBoth(region, 23, 5, false);
      expectBoth(region, 13, 5, true);
    });

    test('선택중 narrows to the copies TOGETHER — the one that only a '
        'single step can say', () {
      final region = CanvasSelectionRegion.combineCopies(
        CanvasSelectionRegion.shape(rect(0, 0, 30, 10)),
        [left, right],
        SelectionCombineMode.intersect,
      );

      expect(
        region,
        isNotNull,
        reason: 'copy-by-copy intersection would have emptied this',
      );
      expectBoth(region!, 3, 5, true);
      expectBoth(region, 23, 5, true);
      expectBoth(region, 13, 5, false);
    });
  });

  group('the union is the same union everywhere', () {
    /// Overlapping copies — the case where an even-odd merge of crossings
    /// would cancel and punch a hole in the middle.
    final overlapA = rect(2, 2, 10, 12);
    final overlapB = rect(6, 2, 14, 12);

    test('the mask agrees with containsPoint over overlapping copies', () {
      final region = CanvasSelectionRegion.combineCopies(
        null,
        [overlapA, overlapB],
        SelectionCombineMode.replace,
      )!;
      final mask = region.maskFor(left: 0, top: 0, width: 16, height: 16);
      for (var y = 0; y < 16; y += 1) {
        for (var x = 0; x < 16; x += 1) {
          expect(
            mask[y * 16 + x] != 0,
            region.containsPoint(at(x + 0.5, y + 0.5)),
            reason: 'mask vs containsPoint at ($x, $y)',
          );
        }
      }
    });

    test('the overlap stays SELECTED — it is a union, not an even-odd '
        'merge', () {
      final region = CanvasSelectionRegion.combineCopies(
        null,
        [overlapA, overlapB],
        SelectionCombineMode.replace,
      )!;
      expectBoth(region, 7, 5, true);
      expectBoth(region, 3, 5, true);
      expectBoth(region, 12, 5, true);
    });

    test('선택중 keeps the whole union when the copies overlap and arrive '
        'RIGHT-first', () {
      // 🚨The ordering case. A row's spans have to be sorted AND merged
      // before an intersect walks them: that walk marches a cursor left to
      // right and clears everything it passes, so a span arriving behind
      // the cursor is silently dropped. Copies come out of the guide in
      // transform order, not in x order — a box on the right of the axis
      // mirrors to the left — so "already sorted" is not something this
      // code may assume.
      final region = CanvasSelectionRegion.combineCopies(
        CanvasSelectionRegion.shape(rect(0, 0, 16, 16)),
        [overlapB, overlapA],
        SelectionCombineMode.intersect,
      )!;

      expectBoth(region, 3, 5, true);
      expectBoth(region, 7, 5, true);
      expectBoth(region, 12, 5, true);
      expectBoth(region, 1, 5, false);
      expectBoth(region, 15, 5, false);
    });

    test('the mask agrees with containsPoint under an overlapping, '
        'right-first 선택중', () {
      final region = CanvasSelectionRegion.combineCopies(
        CanvasSelectionRegion.shape(rect(0, 0, 16, 16)),
        [overlapB, overlapA],
        SelectionCombineMode.intersect,
      )!;
      final mask = region.maskFor(left: 0, top: 0, width: 16, height: 16);
      for (var y = 0; y < 16; y += 1) {
        for (var x = 0; x < 16; x += 1) {
          expect(
            mask[y * 16 + x] != 0,
            region.containsPoint(at(x + 0.5, y + 0.5)),
            reason: 'mask vs containsPoint at ($x, $y)',
          );
        }
      }
    });

    test('and the ants path traces that same union', () {
      final region = CanvasSelectionRegion.combineCopies(
        null,
        [left, right],
        SelectionCombineMode.replace,
      )!;
      final bounds = region
          .pathIn((point) => Offset(point.x, point.y))
          .getBounds();
      expect(bounds.left, 0);
      expect(bounds.right, 26);
      expect(region.selectedBounds.right, 26);
    });
  });

  group('the one-copy case is untouched', () {
    test('combine still folds a lone shape the way it always did', () {
      final region = CanvasSelectionRegion.combine(
        CanvasSelectionRegion.shape(rect(0, 0, 10, 10)),
        rect(20, 0, 30, 10),
        SelectionCombineMode.add,
      )!;
      expectBoth(region, 5, 5, true);
      expectBoth(region, 25, 5, true);
      expectBoth(region, 15, 5, false);
      expect(region.steps.every((step) => step.shapes.length == 1), isTrue);
    });

    test('and a click still deselects in 갱신 only', () {
      final before = CanvasSelectionRegion.shape(rect(0, 0, 10, 10));
      expect(
        CanvasSelectionRegion.combineCopies(
          before,
          const [],
          SelectionCombineMode.replace,
        ),
        isNull,
      );
      expect(
        CanvasSelectionRegion.combineCopies(
          before,
          const [],
          SelectionCombineMode.add,
        ),
        before,
      );
    });

    test('singleShape answers only for ONE polygon in ONE step', () {
      expect(
        CanvasSelectionRegion.shape(rect(0, 0, 10, 10)).singleShape,
        isNotNull,
      );
      expect(
        CanvasSelectionRegion.combineCopies(
          null,
          [left, right],
          SelectionCombineMode.replace,
        )!.singleShape,
        isNull,
        reason: 'the paths that predate the composite model must not take '
            'one copy for the whole selection',
      );
    });
  });
}
