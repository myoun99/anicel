import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/segment_spacing_walk.dart';

/// The one spacing stepper behind the brush dab walk and the cut-stamp
/// drag (the audit's clone scan, 2026-09-06).
void main() {
  List<double> walk({
    required double length,
    required double spacing,
    required double firstAt,
  }) {
    final fractions = <double>[];
    placeAlongSegment(
      length: length,
      spacing: spacing,
      firstAt: firstAt,
      place: fractions.add,
    );
    return fractions;
  }

  test('places the first point at firstAt, then every spacing', () {
    expect(walk(length: 20, spacing: 4, firstAt: 4).map((t) => t * 20), [
      4,
      8,
      12,
      16,
      20,
    ]);
  });

  test('a point exactly at the end is placed (<=, not <)', () {
    expect(walk(length: 5, spacing: 5, firstAt: 5), [1.0]);
    expect(walk(length: 12, spacing: 5, firstAt: 5).map((t) => t * 12), [
      5,
      10,
    ]);
  });

  test('a carry moves the first point closer: firstAt = spacing - carry', () {
    // 3 of the 5 spacing already travelled on the previous segment.
    expect(walk(length: 10, spacing: 5, firstAt: 2).map((t) => t * 10), [2, 7]);
  });

  test('returns the distance of the last point placed', () {
    var count = 0;
    final placed = placeAlongSegment(
      length: 12,
      spacing: 5,
      firstAt: 5,
      place: (_) => count += 1,
    );
    expect(count, 2);
    expect(placed, 10);
  });

  test('when nothing fits it places nothing and returns firstAt - spacing, '
      'so the caller carries the whole segment', () {
    var count = 0;
    final placed = placeAlongSegment(
      length: 3,
      spacing: 5,
      firstAt: 5,
      place: (_) => count += 1,
    );
    expect(count, 0);
    expect(placed, 0);
    // A carried-in start that still does not fit reports the negative
    // distance the previous segment already covered.
    expect(
      placeAlongSegment(length: 1, spacing: 5, firstAt: 2, place: (_) {}),
      -3,
    );
  });
}
