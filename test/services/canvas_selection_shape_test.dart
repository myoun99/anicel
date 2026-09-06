import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

/// The ONE edge/scanline rule behind membership (`containsPoint`, the
/// even-odd ray cast) and the lift mask (`_scanCrossings`, the scanline
/// fill): which edges a horizontal line crosses and where. Both walkers
/// spelled it (the audit's clone scan, 2026-09-06); the strict `>`
/// half-open convention is what keeps a vertex shared by two edges from
/// counting twice.
void main() {
  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);

  group('edgeStraddles', () {
    test('an edge spanning the line straddles it, either way round', () {
      expect(
        CanvasSelectionShape.edgeStraddles(at(0, 0), at(0, 10), 5),
        isTrue,
      );
      expect(
        CanvasSelectionShape.edgeStraddles(at(0, 10), at(0, 0), 5),
        isTrue,
      );
    });

    test('an edge entirely above or below does not', () {
      expect(
        CanvasSelectionShape.edgeStraddles(at(0, 0), at(0, 4), 5),
        isFalse,
      );
      expect(
        CanvasSelectionShape.edgeStraddles(at(0, 6), at(0, 9), 5),
        isFalse,
      );
    });

    test('the convention is half-open: a vertex ON the line belongs to the '
        'edge going UP through it, not the one coming down to it', () {
      // Two edges meeting at y = 5: (0,0)-(0,5) and (0,5)-(0,10). Exactly
      // one of them straddles, so a vertex on the scanline toggles once.
      final down = CanvasSelectionShape.edgeStraddles(at(0, 0), at(0, 5), 5);
      final up = CanvasSelectionShape.edgeStraddles(at(0, 5), at(0, 10), 5);
      expect(down, isFalse);
      expect(up, isTrue);
    });

    test('a horizontal edge never straddles', () {
      expect(
        CanvasSelectionShape.edgeStraddles(at(0, 5), at(9, 5), 5),
        isFalse,
      );
    });
  });

  group('edgeCrossingX', () {
    test('is the x where the edge meets the line', () {
      expect(CanvasSelectionShape.edgeCrossingX(at(0, 0), at(10, 10), 5), 5);
      expect(
        CanvasSelectionShape.edgeCrossingX(at(10, 0), at(0, 10), 2.5),
        7.5,
      );
    });

    test('a vertical edge crosses at its own x', () {
      expect(CanvasSelectionShape.edgeCrossingX(at(3, 0), at(3, 10), 7), 3);
    });
  });

  test('containsPoint is the even-odd cast over the same rule', () {
    final square = CanvasSelectionShape.rect(
      left: 2,
      top: 2,
      right: 6,
      bottom: 6,
    );
    expect(square.containsPoint(at(4, 4)), isTrue);
    expect(square.containsPoint(at(1, 4)), isFalse);
    expect(square.containsPoint(at(7, 4)), isFalse);
    // Half-open on the left edge: x == left is inside, x == right is not.
    expect(square.containsPoint(at(2, 4)), isTrue);
    expect(square.containsPoint(at(6, 4)), isFalse);
    // And on the top edge: y == top is inside, y == bottom is not.
    expect(square.containsPoint(at(4, 2)), isTrue);
    expect(square.containsPoint(at(4, 6)), isFalse);
  });
}
