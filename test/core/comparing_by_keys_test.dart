import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/comparing_by_keys.dart';

/// The lexicographic key-tuple comparator that three hand-written
/// comparators in the cache invalidation plan used to spell out.
void main() {
  group('comparingByKeys', () {
    final byNameThenAge = comparingByKeys<({String name, int age})>(
      (item) => [item.name, item.age],
    );

    test('the FIRST key decides when it differs', () {
      expect(
        byNameThenAge((name: 'a', age: 9), (name: 'b', age: 1)),
        lessThan(0),
      );
      expect(
        byNameThenAge((name: 'b', age: 1), (name: 'a', age: 9)),
        greaterThan(0),
      );
    });

    test('a tie on the first key falls through to the next', () {
      expect(
        byNameThenAge((name: 'a', age: 1), (name: 'a', age: 2)),
        lessThan(0),
      );
      expect(
        byNameThenAge((name: 'a', age: 2), (name: 'a', age: 1)),
        greaterThan(0),
      );
    });

    test('equal key lists compare as 0', () {
      expect(byNameThenAge((name: 'a', age: 1), (name: 'a', age: 1)), 0);
    });

    test('sorts a list by the tuple, in key order', () {
      final items = [
        (name: 'b', age: 1),
        (name: 'a', age: 2),
        (name: 'a', age: 1),
      ]..sort(byNameThenAge);
      expect(items, [
        (name: 'a', age: 1),
        (name: 'a', age: 2),
        (name: 'b', age: 1),
      ]);
    });
  });
}
