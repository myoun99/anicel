import 'package:anicel/src/core/segment_share.dart';
import 'package:flutter_test/flutter_test.dart';

/// ONE PROJECTION of a point onto a segment — a model point's, the colour
/// wheel's triangle edge and a header graph's line (I-3 ④) all ask it.
void main() {
  const a = Offset.zero;
  const b = Offset(10, 0);

  test('where a point falls along a segment: 0 at its start, 1 at its end, '
      'past either as far as it is — and 0 on a segment that is one '
      'point', () {
    expect(shareAlongSegment(const Offset(5, 3), a, b), 0.5);
    expect(shareAlongSegment(const Offset(15, -2), a, b), 1.5);
    expect(shareAlongSegment(const Offset(-5, 7), a, b), -0.5);
    expect(shareAlongSegment(const Offset(3, 4), a, a), 0);
  });

  test('a segment is followed across as well as along', () {
    expect(shareAlongSegment(const Offset(3, 5), a, const Offset(0, 10)), 0.5);
    expect(shareAlongSegment(const Offset(4, 0), a, const Offset(4, 4)), 0.5);
  });

  test('the point of a segment nearest a point is on it, its ends '
      'included', () {
    expect(nearestOnSegment(const Offset(5, 3), a, b), const Offset(5, 0));
    expect(nearestOnSegment(const Offset(15, -2), a, b), b);
    expect(nearestOnSegment(const Offset(-5, 7), a, b), a);
  });
}
