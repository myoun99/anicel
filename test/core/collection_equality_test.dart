import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/collection_equality.dart';

/// These three helpers back the `==` of most model classes, yet nothing
/// named them directly — they were only exercised through those models'
/// equality tests. Pin the contract here so it survives model-test churn.
void main() {
  group('listEquals', () {
    test('identical, equal-by-value, and length/element differences', () {
      final a = [1, 2, 3];
      expect(listEquals(a, a), isTrue, reason: 'identical');
      expect(listEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(listEquals([1, 2, 3], [1, 2]), isFalse, reason: 'length');
      expect(listEquals([1, 2, 3], [1, 9, 3]), isFalse, reason: 'element');
    });

    test('order matters and empty lists are equal', () {
      expect(listEquals([1, 2], [2, 1]), isFalse);
      expect(listEquals<int>([], []), isTrue);
    });

    test('uses element == (value objects), not identity', () {
      expect(
        listEquals(
          [const _Val(1), const _Val(2)],
          [const _Val(1), const _Val(2)],
        ),
        isTrue,
      );
    });
  });

  group('setEquals', () {
    test('same members regardless of iteration order', () {
      expect(setEquals({1, 2, 3}, {3, 2, 1}), isTrue);
      expect(setEquals({1, 2}, {1, 2, 3}), isFalse, reason: 'length');
      expect(setEquals({1, 2, 3}, {1, 2, 9}), isFalse, reason: 'member');
      expect(setEquals<int>({}, {}), isTrue);
    });

    test('identical short-circuits', () {
      final s = {1, 2};
      expect(setEquals(s, s), isTrue);
    });
  });

  group('mapEquals', () {
    test('same keys mapped to equal values', () {
      expect(mapEquals({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
      expect(mapEquals({'a': 1}, {'a': 1, 'b': 2}), isFalse, reason: 'length');
      expect(mapEquals({'a': 1}, {'b': 1}), isFalse, reason: 'key');
      expect(mapEquals({'a': 1}, {'a': 2}), isFalse, reason: 'value');
      expect(mapEquals<String, int>({}, {}), isTrue);
    });

    test('identical short-circuits', () {
      final m = {'a': 1};
      expect(mapEquals(m, m), isTrue);
    });
  });
}

class _Val {
  const _Val(this.n);
  final int n;
  @override
  bool operator ==(Object other) => other is _Val && other.n == n;
  @override
  int get hashCode => n.hashCode;
}
