import 'package:anicel/src/native/qa_pen_points.dart';
import 'package:flutter_test/flutter_test.dart';

/// H59 법 A (card pen-points-are-taken-off-the-ui-thread): what messages'
/// points lost before the book reaches the app by the book's own name —
/// none in a process no reader wrote in.
void main() {
  test('the point book says what it lost, by why — none yet', () {
    expect(QaPenPoints.lost, (full: 0, unread: 0, cut: 0));
  });
}
