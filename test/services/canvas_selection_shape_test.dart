import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

/// The hit test (`containsPoint`): the even-odd cast by the engine's own
/// integer inequality (gpu-int-spec-canvas 1b S1) — every point in Q.8, an
/// edge crossing a point's line half-open, counted where it crosses right
/// of the point —, so a pixel centre is in exactly when the engine's mask
/// holds it. ↩️It shared an f64 rule with the lift mask's CPU scanline
/// (the audit's clone scan, 2026-09-06) until the mask was the engine's.
void main() {
  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);

  test('inside is half-open: the left and top edges are in, the right and '
      'bottom ones out', () {
    final square = CanvasSelectionShape.rect(
      left: 2,
      top: 2,
      right: 6,
      bottom: 6,
    );
    expect(square.containsPoint(at(4, 4)), isTrue);
    expect(square.containsPoint(at(1, 4)), isFalse);
    expect(square.containsPoint(at(7, 4)), isFalse);
    expect(square.containsPoint(at(2, 4)), isTrue);
    expect(square.containsPoint(at(6, 4)), isFalse);
    expect(square.containsPoint(at(4, 2)), isTrue);
    expect(square.containsPoint(at(4, 6)), isFalse);
  });

  test('a vertex on the point\'s line toggles once — the edge going on past '
      'it, not the one that ends there', () {
    // The line y = 5 meets the tip (10, 5): counted twice, the point left
    // of it would read as outside.
    final arrow = CanvasSelectionShape([at(0, 0), at(10, 5), at(0, 10)]);
    expect(arrow.containsPoint(at(5, 5)), isTrue);
    expect(arrow.containsPoint(at(11, 5)), isFalse);
  });

  test('an edge counts whichever way it runs — up the left side and down '
      'the right as much as the other way round', () {
    final clockwise = CanvasSelectionShape([
      at(1, 1),
      at(5, 1),
      at(5, 5),
      at(1, 5),
    ]);
    final anticlockwise = CanvasSelectionShape([
      at(1, 1),
      at(1, 5),
      at(5, 5),
      at(5, 1),
    ]);
    for (final shape in [clockwise, anticlockwise]) {
      expect(shape.containsPoint(at(3, 3)), isTrue);
      expect(shape.containsPoint(at(0.5, 3)), isFalse);
      expect(shape.containsPoint(at(5.5, 3)), isFalse);
    }
  });

  test('🚨a point is rounded to 1/256 px as the engine rounds the mask\'s: a '
      'right edge at 7.501 is at 7.5, and the centre on it is out — as it '
      'is out of the pixels a lift takes', () {
    final shape = CanvasSelectionShape.rect(
      left: 3,
      top: 0,
      right: 7.501,
      bottom: 1,
    );
    expect(shape.containsPoint(at(7.5, 0.5)), isFalse);
    expect(shape.containsPoint(at(6.5, 0.5)), isTrue);
    expect(
      CanvasSelectionRegion.shape(
        shape,
      ).pixelRunsFor(left: 0, top: 0, width: 10, height: 1),
      [
        [3, 7],
      ],
    );
  });

  test('…and to the NEAREST 1/256 px: a right edge at 7.503 is past 7.5, '
      'and the centre on 7.5 is in — for the hit test as for the mask', () {
    final shape = CanvasSelectionShape.rect(
      left: 3,
      top: 0,
      right: 7.503,
      bottom: 1,
    );
    expect(shape.containsPoint(at(7.5, 0.5)), isTrue);
    expect(
      CanvasSelectionRegion.shape(
        shape,
      ).pixelRunsFor(left: 0, top: 0, width: 10, height: 1),
      [
        [3, 8],
      ],
    );
  });

  test('🚨every pixel centre of a lasso off the pixel grid is in for the hit '
      'test exactly when the engine\'s mask holds it', () {
    final lasso = CanvasSelectionShape([
      at(1.3, 0.7),
      at(13.501, 2.25),
      at(9.749, 6.4999),
      at(14.2, 12.6),
      at(6.0039, 9.5),
      at(0.4, 13.1),
      at(4.75, 6.5002),
    ]);
    final rows = CanvasSelectionRegion.shape(
      lasso,
    ).pixelRunsFor(left: 0, top: 0, width: 16, height: 16);
    for (var y = 0; y < 16; y += 1) {
      final runs = rows[y];
      bool held(int x) {
        for (var r = 0; r + 1 < runs.length; r += 2) {
          if (x >= runs[r] && x < runs[r + 1]) {
            return true;
          }
        }
        return false;
      }

      for (var x = 0; x < 16; x += 1) {
        expect(
          lasso.containsPoint(at(x + 0.5, y + 0.5)),
          held(x),
          reason: 'the centre of ($x, $y)',
        );
      }
    }
  });
}
