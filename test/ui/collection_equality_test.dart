// A MAP OF LISTS COMPARES ITS LISTS BY CONTENT — `mapEquals` compares
// them by identity, which a rebuilt list never satisfies.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/collection_equality.dart';

void main() {
  group('mapOfListsEquals', () {
    test('rebuilt lists with the same elements are equal', () {
      expect(
        mapOfListsEquals(
          {
            'a': [1, 2],
            'b': <int>[],
          },
          {
            'a': [1, 2],
            'b': <int>[],
          },
        ),
        isTrue,
      );
    });

    test('a differing element, a missing key or an extra key is unequal', () {
      expect(
        mapOfListsEquals(
          {
            'a': [1, 2],
          },
          {
            'a': [1, 3],
          },
        ),
        isFalse,
      );
      expect(
        mapOfListsEquals(
          {
            'a': [1],
          },
          {
            'b': [1],
          },
        ),
        isFalse,
      );
      expect(
        mapOfListsEquals(
          {
            'a': [1],
          },
          {
            'a': [1],
            'b': [1],
          },
        ),
        isFalse,
      );
    });

    test('null equals only null', () {
      expect(mapOfListsEquals<String, int>(null, null), isTrue);
      expect(mapOfListsEquals<String, int>(null, {}), isFalse);
      expect(mapOfListsEquals<String, int>({}, null), isFalse);
    });
  });

  group('the hashes', () {
    test('equal maps of lists hash equal, whatever the entry order', () {
      expect(
        mapOfListsHash({
          'a': [1, 2],
          'b': [3],
        }),
        mapOfListsHash({
          'b': [3],
          'a': [1, 2],
        }),
      );
    });

    test('equal maps hash equal, whatever the entry order', () {
      expect(mapHash({'a': 1, 'b': 2}), mapHash({'b': 2, 'a': 1}));
    });

    test('null hashes as null', () {
      expect(mapHash<String, int>(null), null.hashCode);
      expect(mapOfListsHash<String, int>(null), null.hashCode);
    });
  });
}
