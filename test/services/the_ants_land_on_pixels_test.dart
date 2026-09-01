import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// 🚨★★★유저 (F-65): 「선택툴 선택할때, 라이브로 선택중일땐 선이 픽셀에
/// 안착안된 벡터로 보여도 상관없는데, **선택 커밋될떈 픽셀에 제대로 안착한
/// 상태로**. 지금은 **변형되는 픽셀 범위와 개미행렬 위치가 다르다**」.
///
/// The two answers came from different rules and always had: membership is
/// by PIXEL CENTRE ([CanvasSelectionRegion.maskFor] scans `y + 0.5`), while
/// the ants traced [CanvasSelectionRegion.pathIn] — the polygon itself. They
/// AGREE about which pixels are in; they disagree about where the line is,
/// and at any zoom past 1:1 that gap is what the user is looking at.
///
/// ⚠️These drive the region rather than the painter: this is a fact about
/// the selection, and the painter is one of several readers.
void main() {
  CanvasSelectionRegion regionOf(CanvasSelectionShape shape) =>
      CanvasSelectionRegion([
        CanvasSelectionStep.copies([shape], SelectionCombineMode.replace),
      ]);

  /// A rectangle whose every edge falls BETWEEN pixel centres — the case
  /// the eye catches, and the case a whole-number fixture would hide.
  CanvasSelectionRegion fractionalRect() => regionOf(
    CanvasSelectionShape.rect(left: 10.3, top: 20.7, right: 30.4, bottom: 40.2),
  );

  /// Which pixels are actually selected, straight off the lift's own
  /// rasteriser — the answer the ants have to match.
  Set<(int, int)> selectedPixels(
    CanvasSelectionRegion region, {
    int left = 0,
    int top = 0,
    int width = 64,
    int height = 64,
  }) {
    final mask = region.maskFor(
      left: left,
      top: top,
      width: width,
      height: height,
    );
    return {
      for (var y = 0; y < height; y += 1)
        for (var x = 0; x < width; x += 1)
          if (mask[y * width + x] != 0) (left + x, top + y),
    };
  }

  test('the fixture really is off-grid', () {
    // ★The premise. With integer edges the outline and the polygon would
    // coincide and every assertion below would pass without a fix.
    final pixels = selectedPixels(fractionalRect());
    expect(pixels, isNotEmpty);
    final xs = pixels.map((p) => p.$1);
    final ys = pixels.map((p) => p.$2);
    expect(
      (xs.reduce((a, b) => a < b ? a : b), xs.reduce((a, b) => a > b ? a : b)),
      (10, 29),
      reason: 'centres 10.5…29.5 are inside 10.3…30.4; 30.5 is not',
    );
    expect(
      (ys.reduce((a, b) => a < b ? a : b), ys.reduce((a, b) => a > b ? a : b)),
      (21, 39),
      reason: 'centres 21.5…39.5 are inside 20.7…40.2',
    );

    final polygon = fractionalRect()
        .pathIn((point) => ui.Offset(point.x, point.y))
        .getBounds();
    // ⚠️Side by side rather than `Rect` equality: `Path.getBounds` comes
    // back through Skia's FLOAT32, so 10.3 returns as 10.300000190734863 and
    // an exact compare fails while printing two identical-looking rects.
    for (final (name, actual, want) in <(String, double, double)>[
      ('left', polygon.left, 10.3),
      ('top', polygon.top, 20.7),
      ('right', polygon.right, 30.4),
      ('bottom', polygon.bottom, 40.2),
    ]) {
      expect(
        actual,
        closeTo(want, 1e-4),
        reason:
            'the vector outline sits where the drag did — $name is off '
            'the grid',
      );
    }
  });

  test('the committed outline lands on the pixel grid', () {
    final outline = fractionalRect().pixelOutlineIn(
      (point) => ui.Offset(point.x, point.y),
    );

    expect(
      outline.getBounds(),
      const ui.Rect.fromLTRB(10, 21, 30, 40),
      reason:
          'the box around the SELECTED PIXELS — [10, 29] × [21, 39] '
          'inclusive, so its right/bottom edges are 30 and 40',
    );
  });

  test('every pixel the mask selects is inside the outline, and no other', () {
    final region = fractionalRect();
    final outline = region.pixelOutlineIn(
      (point) => ui.Offset(point.x, point.y),
    );
    final pixels = selectedPixels(region);

    // ⛔The whole point of the round: the ants and the lift must answer the
    // same way about every pixel, and the outline is what the user sees.
    for (var y = 18; y < 44; y += 1) {
      for (var x = 7; x < 34; x += 1) {
        expect(
          outline.contains(ui.Offset(x + 0.5, y + 0.5)),
          pixels.contains((x, y)),
          reason: 'pixel ($x, $y)',
        );
      }
    }
  });

  test('a hole from a subtraction is traced too', () {
    final region = CanvasSelectionRegion([
      CanvasSelectionStep.copies([
        CanvasSelectionShape.rect(left: 4, top: 4, right: 20, bottom: 20),
      ], SelectionCombineMode.replace),
      CanvasSelectionStep.copies([
        CanvasSelectionShape.rect(left: 9.4, top: 9.6, right: 14.2, bottom: 15),
      ], SelectionCombineMode.subtract),
    ]);
    final outline = region.pixelOutlineIn(
      (point) => ui.Offset(point.x, point.y),
    );
    final pixels = selectedPixels(region);

    expect(
      pixels.contains((11, 12)),
      isFalse,
      reason: 'the premise: that pixel really was taken back',
    );
    expect(
      outline.contains(const ui.Offset(11.5, 12.5)),
      isFalse,
      reason: 'so the ants must go around it, not over it',
    );
    expect(outline.contains(const ui.Offset(5.5, 5.5)), isTrue);
  });

  // ⚠️The straight-run merge, which nothing else here can see: the walk
  // emits one vertex per pixel EDGE, so without it a plain rectangle would
  // arrive as four sides of twenty and nineteen points and be rebuilt into
  // a `Path` on every animation tick. 🧪Measured by turning the merge off:
  // every other test in this file stayed green.
  test('straight runs collapse — a rectangle is four points', () {
    final contours = fractionalRect().pixelOutlineContours;

    expect(contours, hasLength(1), reason: 'one component, one contour');
    expect(
      contours.single,
      hasLength(4),
      reason: 'a rectangle has four corners however many pixels it spans',
    );
  });

  test('a staircase keeps its steps', () {
    // ⛔The merge must not straighten what is genuinely a staircase. A
    // triangle's hypotenuse is one step per row, and every one of them is a
    // corner the user can see at zoom.
    final region = regionOf(
      CanvasSelectionShape([
        CanvasPoint(x: 4, y: 4),
        CanvasPoint(x: 24, y: 4),
        CanvasPoint(x: 4, y: 24),
      ]),
    );
    final points = region.pixelOutlineContours.single;

    expect(
      points.length,
      greaterThan(20),
      reason: 'the diagonal is a staircase and stays one',
    );
  });

  test('an empty fold traces nothing rather than throwing', () {
    final region = CanvasSelectionRegion([
      CanvasSelectionStep.copies([
        CanvasSelectionShape.rect(left: 4, top: 4, right: 8, bottom: 8),
      ], SelectionCombineMode.replace),
      CanvasSelectionStep.copies([
        CanvasSelectionShape.rect(left: 0, top: 0, right: 40, bottom: 40),
      ], SelectionCombineMode.subtract),
    ]);
    expect(
      region
          .pixelOutlineIn((point) => ui.Offset(point.x, point.y))
          .getBounds()
          .isEmpty,
      isTrue,
    );
  });
}
