import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// R26 #16: the composite region model — the four modes fold into ONE
/// membership rule that the hit test, the lift mask and the ants all read.
void main() {
  CanvasSelectionShape rect(double l, double t, double r, double b) =>
      CanvasSelectionShape.rect(left: l, top: t, right: r, bottom: b);

  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);

  /// Membership straight off the MASK (the lift's own rasterizer) so the
  /// two paths are pinned against each other, not just against themselves.
  bool maskSays(CanvasSelectionRegion region, int x, int y) {
    final mask = region.maskFor(left: x, top: y, width: 1, height: 1);
    return mask[0] != 0;
  }

  void expectBoth(CanvasSelectionRegion region, int x, int y, bool inside) {
    expect(
      region.containsPoint(at(x + 0.5, y + 0.5)),
      inside,
      reason: 'containsPoint($x, $y)',
    );
    expect(maskSays(region, x, y), inside, reason: 'mask($x, $y)');
  }

  group('fold semantics', () {
    test('a single shape is the plain P9 polygon', () {
      final region = CanvasSelectionRegion.shape(rect(0, 0, 10, 10));
      expectBoth(region, 5, 5, true);
      expectBoth(region, 15, 5, false);
      expect(region.singleShape, isNotNull);
    });

    test('추가 unions: both lobes select, the gap between them does not', () {
      final region = CanvasSelectionRegion.combine(
        CanvasSelectionRegion.shape(rect(0, 0, 10, 10)),
        rect(20, 0, 30, 10),
        SelectionCombineMode.add,
      )!;
      expectBoth(region, 5, 5, true);
      expectBoth(region, 25, 5, true);
      expectBoth(region, 15, 5, false);
    });

    test('삭제 cuts a hole out of the region', () {
      final region = CanvasSelectionRegion.combine(
        CanvasSelectionRegion.shape(rect(0, 0, 20, 20)),
        rect(5, 5, 15, 15),
        SelectionCombineMode.subtract,
      )!;
      expectBoth(region, 2, 2, true);
      expectBoth(region, 10, 10, false);
      expectBoth(region, 18, 18, true);
    });

    test('선택중 keeps only the overlap', () {
      final region = CanvasSelectionRegion.combine(
        CanvasSelectionRegion.shape(rect(0, 0, 20, 20)),
        rect(10, 10, 30, 30),
        SelectionCombineMode.intersect,
      )!;
      expectBoth(region, 15, 15, true);
      expectBoth(region, 5, 5, false);
      expectBoth(region, 25, 25, false);
    });

    test('갱신 throws the previous steps away entirely', () {
      final built = CanvasSelectionRegion.combine(
        CanvasSelectionRegion.shape(rect(0, 0, 10, 10)),
        rect(20, 0, 30, 10),
        SelectionCombineMode.add,
      )!;
      final replaced = CanvasSelectionRegion.combine(
        built,
        rect(40, 0, 50, 10),
        SelectionCombineMode.replace,
      )!;
      expect(replaced.steps, hasLength(1));
      expectBoth(replaced, 5, 5, false);
      expectBoth(replaced, 45, 5, true);
    });

    test('three steps fold left to right (add then subtract then add)', () {
      var region = CanvasSelectionRegion.shape(rect(0, 0, 20, 20));
      region = region.combinedWith(
        rect(5, 5, 15, 15),
        SelectionCombineMode.subtract,
      )!;
      region = region.combinedWith(
        rect(8, 8, 12, 12),
        SelectionCombineMode.add,
      )!;
      expectBoth(region, 2, 2, true); // outer ring
      expectBoth(region, 6, 6, false); // hole
      expectBoth(region, 10, 10, true); // island back inside the hole
    });
  });

  group('empty-region rules', () {
    test('삭제/선택중 with nothing selected stays nothing', () {
      expect(
        CanvasSelectionRegion.combine(
          null,
          rect(0, 0, 10, 10),
          SelectionCombineMode.subtract,
        ),
        isNull,
      );
      expect(
        CanvasSelectionRegion.combine(
          null,
          rect(0, 0, 10, 10),
          SelectionCombineMode.intersect,
        ),
        isNull,
      );
    });

    test('추가 with nothing selected starts a region', () {
      expect(
        CanvasSelectionRegion.combine(
          null,
          rect(0, 0, 10, 10),
          SelectionCombineMode.add,
        ),
        isNotNull,
      );
    });

    test('a click (null polygon) deselects in 갱신 only', () {
      final region = CanvasSelectionRegion.shape(rect(0, 0, 10, 10));
      expect(
        CanvasSelectionRegion.combine(
          region,
          null,
          SelectionCombineMode.replace,
        ),
        isNull,
      );
      for (final mode in [
        SelectionCombineMode.add,
        SelectionCombineMode.subtract,
        SelectionCombineMode.intersect,
      ]) {
        expect(
          CanvasSelectionRegion.combine(region, null, mode),
          same(region),
          reason: '$mode leaves the region alone',
        );
      }
    });
  });

  group('geometry', () {
    test('bounds cover every ADDING step (subtract only shrinks)', () {
      var region = CanvasSelectionRegion.shape(rect(0, 0, 10, 10));
      region = region.combinedWith(
        rect(20, 30, 40, 50),
        SelectionCombineMode.add,
      )!;
      region = region.combinedWith(
        rect(-100, -100, 100, 100),
        SelectionCombineMode.subtract,
      )!;
      final bounds = region.bounds;
      expect(bounds.left, 0);
      expect(bounds.top, 0);
      expect(bounds.right, 40);
      expect(bounds.bottom, 50);
    });

    test('translate moves every step together', () {
      final region = CanvasSelectionRegion.shape(
        rect(0, 0, 10, 10),
      ).combinedWith(rect(4, 4, 6, 6), SelectionCombineMode.subtract)!;
      final moved = region.translated(dx: 100, dy: 0);
      expectBoth(moved, 101, 5, true);
      expectBoth(moved, 105, 5, false);
      expectBoth(moved, 5, 5, false);
    });

    test('value equality compares the step list', () {
      final a = CanvasSelectionRegion.shape(rect(0, 0, 10, 10));
      final b = CanvasSelectionRegion.shape(rect(0, 0, 10, 10));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.combinedWith(rect(1, 1, 2, 2), SelectionCombineMode.add), isFalse);
    });
  });

  group('mask rasterization', () {
    test('the mask agrees with containsPoint across a whole box', () {
      final region = CanvasSelectionRegion.shape(
        rect(2, 2, 12, 12),
      ).combinedWith(rect(5, 5, 9, 9), SelectionCombineMode.subtract)!;
      final mask = region.maskFor(left: 0, top: 0, width: 16, height: 16);
      for (var y = 0; y < 16; y += 1) {
        for (var x = 0; x < 16; x += 1) {
          expect(
            mask[y * 16 + x] != 0,
            region.containsPoint(at(x + 0.5, y + 0.5)),
            reason: 'disagreement at ($x, $y)',
          );
        }
      }
    });

    test('an intersect step clears the row OUTSIDE its spans', () {
      final region = CanvasSelectionRegion.shape(
        rect(0, 0, 16, 16),
      ).combinedWith(rect(4, 0, 8, 16), SelectionCombineMode.intersect)!;
      final mask = region.maskFor(left: 0, top: 0, width: 16, height: 1);
      for (var x = 0; x < 16; x += 1) {
        expect(mask[x] != 0, x >= 4 && x < 8, reason: 'column $x');
      }
    });
  });
}
