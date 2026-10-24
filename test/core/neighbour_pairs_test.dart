import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/neighbour_pairs.dart';

void main() {
  test('each item comes with the one after it, in order', () {
    expect(neighbourPairs(['a', 'b', 'c', 'd']).toList(), [
      ('a', 'b'),
      ('b', 'c'),
      ('c', 'd'),
    ]);
  });

  test('fewer than two make no pair', () {
    expect(neighbourPairs(<int>[]), isEmpty);
    expect(neighbourPairs([7]), isEmpty);
  });
}
