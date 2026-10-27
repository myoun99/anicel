import 'package:anicel/src/core/one_way.dart';
import 'package:flutter_test/flutter_test.dart';

/// ONE answer for which way a hand went, and a drag kept to it — a canvas
/// drag's Shift (I-136), a graph's (I-3 ③), a pair of scales scrubbed one
/// at a time, and a two-finger flip's way.
void main() {
  test('the way it went further is kept, the other part is 0', () {
    expect(keptToOneWay(30.4, -20.6), (30.4, 0.0));
    expect(keptToOneWay(5, -40), (0.0, -40.0));
    expect(keptToOneWay(-7, 3), (-7.0, 0.0), reason: 'by how far, not which '
        'way round');
  });

  test('a tie is the first way\'s', () {
    expect(wentFurtherAlongFirst(-4, 4), isTrue);
    expect(keptToOneWay(4, -4), (4.0, 0.0));
    expect(wentFurtherAlongFirst(3.9, 4), isFalse);
  });

  test('a hand that has not moved stays where it is', () {
    expect(keptToOneWay(0, 0), (0.0, 0.0));
  });
}
