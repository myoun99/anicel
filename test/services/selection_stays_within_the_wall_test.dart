import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// 🚨I-23 — A SELECTION NEVER REACHES PAST THE PASTEBOARD WALL.
///
/// 유저 2026-09-30, answering I-23-Q1: 「선택도구로 사용할수있는
/// 모든부분까지임. 근데 지금 보니까 페이스트보드 밖도 선택가능하네? 해당부분
/// 안으로만 가능하게 구조적으로 변경하면서 작업」.
///
/// The model half of the door, [CanvasSelectionRegion.clippedTo]. Every pin
/// reads PIXELS over a ring that reaches past the wall on every side: what
/// the cut must not change is which pixels are in, and the polygon's points
/// are free to move.
void main() {
  /// A small stand-in for a pasteboard wall.
  const wall = ui.Rect.fromLTRB(0, 0, 40, 30);

  /// The ring the pins read: the wall, and ten pixels past every side.
  const ringLeft = -10;
  const ringTop = -10;
  const ringWidth = 60;
  const ringHeight = 50;

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

  /// [cut] selects exactly [original]'s pixels inside the wall and not one
  /// outside it, its hit test agrees with its mask at every pixel, and its
  /// coverage box lies inside the wall.
  void expectCutAtTheWall(
    CanvasSelectionRegion original,
    CanvasSelectionRegion? cut,
  ) {
    expect(cut, isNotNull, reason: 'something was inside the wall');
    final before = ringMask(original);
    final after = ringMask(cut!);
    var past = 0;
    var kept = 0;
    for (var row = 0; row < ringHeight; row += 1) {
      for (var column = 0; column < ringWidth; column += 1) {
        final x = ringLeft + column;
        final y = ringTop + row;
        final index = row * ringWidth + column;
        if (!insideWall(x, y) && before[index] != 0) {
          past += 1;
        }
        final want = insideWall(x, y) && before[index] != 0;
        if (want) {
          kept += 1;
        }
        expect(after[index] != 0, want, reason: 'mask at ($x, $y)');
        expect(
          cut.containsPoint(at(x + 0.5, y + 0.5)),
          want,
          reason: 'containsPoint at ($x, $y)',
        );
      }
    }
    expect(past, greaterThan(0), reason: 'the premise: it reached past');
    expect(kept, greaterThan(0), reason: 'the premise: some was inside');
    final box = cut.coverageBounds;
    expect(box.left, greaterThanOrEqualTo(wall.left));
    expect(box.top, greaterThanOrEqualTo(wall.top));
    expect(box.right, lessThanOrEqualTo(wall.right));
    expect(box.bottom, lessThanOrEqualTo(wall.bottom));
  }

  // ⚠️Off-grid points on purpose: a pixel centre lying EXACTLY on an edge
  // would be decided by rounding in the cut's crossing, which is a fact
  // about floating point and not about the wall.
  final lasso = CanvasSelectionRegion.shape(
    CanvasSelectionShape([
      at(-8.3, 6.2),
      at(18.6, -7.1),
      at(47.4, 9.7),
      at(30.9, 36.3),
      at(12.2, 18.8),
      at(4.1, 33.6),
    ]),
  );

  test('a lasso across the wall keeps what is inside, pixel for pixel', () {
    expectCutAtTheWall(lasso, lasso.clippedTo(wall));
  });

  test('an arch whose crown is past the wall keeps its gap unselected', () {
    // The Sutherland–Hodgman artefact, provoked: the arch leaves through
    // the top of the wall in one arm and comes back in the other, so the
    // cut joins the arms with a run ALONG the wall line. That run lies on
    // the line, where no pixel centre is — the gap under it stays empty.
    final arch = CanvasSelectionRegion.shape(
      CanvasSelectionShape([
        at(5, 26),
        at(5, -8),
        at(35, -8),
        at(35, 26),
        at(26, 26),
        at(26, -2),
        at(14, -2),
        at(14, 26),
      ]),
    );
    final cut = arch.clippedTo(wall);

    expectCutAtTheWall(arch, cut);
    expect(cut!.containsPoint(at(20.5, 4.5)), isFalse, reason: 'the gap');
    expect(cut.containsPoint(at(9.5, 4.5)), isTrue, reason: 'an arm');
  });

  test('a figure-8 across the wall keeps both lobes as they were', () {
    // Self-crossing: the even-odd rule decides its inside, and the cut
    // must not change that rule's answer anywhere inside the wall.
    final bowTie = CanvasSelectionRegion.shape(
      CanvasSelectionShape([at(-10, 5), at(30, 25), at(30, 5), at(-10, 25)]),
    );

    expectCutAtTheWall(bowTie, bowTie.clippedTo(wall));
  });

  test('a selection already inside comes back as ITSELF — a 삭제 reaching '
      'past the wall takes nothing that is not there', () {
    final inside = CanvasSelectionRegion.shape(
      rect(5, 5, 20, 20),
    ).combinedWith(rect(10, 10, 60, 15), SelectionCombineMode.subtract)!;

    expect(inside.clippedTo(wall), same(inside));
  });

  test('cutting twice is cutting once', () {
    final once = lasso.clippedTo(wall)!;

    expect(once.clippedTo(wall), same(once));
  });

  group('a shape wholly past the wall', () {
    final before = CanvasSelectionRegion.shape(rect(5, 5, 20, 20));
    final past = rect(50, 5, 60, 20);

    test('갱신 with it leaves nothing selected', () {
      expect(
        CanvasSelectionRegion.combine(
          before,
          past,
          SelectionCombineMode.replace,
        )!.clippedTo(wall),
        isNull,
      );
    });

    test('추가 with it changes nothing', () {
      final added = before.combinedWith(past, SelectionCombineMode.add)!;

      expect(added.clippedTo(wall), before);
    });

    test('삭제 with it takes nothing away', () {
      final taken = before.combinedWith(past, SelectionCombineMode.subtract)!;

      expect(ringMask(taken.clippedTo(wall)!), ringMask(before));
    });

    test('a selection that STARTED past the wall drops out, and what was '
        'added after it starts the selection', () {
      // The fold empties where its first outline vanishes, and the next
      // surviving 추가 has nothing before it — so it lands as a 갱신.
      final startedPast = CanvasSelectionRegion.shape(
        past,
      ).combinedWith(rect(5, 5, 20, 20), SelectionCombineMode.add)!;

      expect(startedPast.clippedTo(wall), before);
    });

    test('선택중 with it leaves nothing — even from a selection that '
        'reached past the wall itself', () {
      // Kept from a larger cut's wall: the cut is not asked of it until a
      // door is, and here one is. What 선택중 keeps is past the wall.
      final kept = CanvasSelectionRegion.shape(rect(30, 5, 55, 20));
      final narrowed = kept.combinedWith(
        past,
        SelectionCombineMode.intersect,
      )!;

      expect(narrowed.clippedTo(wall), isNull);
    });
  });

  test('an inverse carried half past the wall keeps its hole', () {
    // The wall minus a square, the shape I-23's inverse takes — built
    // straight from the steps, so this pins the nested operand's cut.
    final inverse = CanvasSelectionRegion([
      CanvasSelectionStep(
        rect(wall.left, wall.top, wall.right, wall.bottom),
        SelectionCombineMode.replace,
      ),
      CanvasSelectionStep.region(
        CanvasSelectionRegion.shape(rect(8, 8, 16, 16)),
        SelectionCombineMode.subtract,
      ),
    ]);
    final carried = inverse.translated(dx: 20, dy: 0);
    final cut = carried.clippedTo(wall);

    expectCutAtTheWall(carried, cut);
    expect(cut!.containsPoint(at(30.5, 12.5)), isFalse, reason: 'the hole');
    expect(cut.containsPoint(at(25.5, 12.5)), isTrue, reason: 'around it');
    expect(
      cut.containsPoint(at(10.5, 12.5)),
      isFalse,
      reason: 'the carried wall starts at 20',
    );
  });
}
