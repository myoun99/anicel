import 'dart:isolate';

import 'package:anicel/src/core/frozen_collections.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🔬Card a-track-copy-wraps-its-unchanged-lists-anew (11-11): a model
/// freezes what it is given through one helper, which hands a collection
/// it froze back as itself — and copies one from outside, as it always
/// did.
void main() {
  group('a list', () {
    test('frozen here is handed on as itself', () {
      final frozen = frozenList([1, 2, 3]);
      expect(identical(frozenList(frozen), frozen), isTrue);
    });

    test('from outside is copied, and changing it changes nothing', () {
      final outside = [1, 2, 3];
      final frozen = frozenList(outside);
      expect(identical(frozen, outside), isFalse);
      outside.add(4);
      expect(frozen, [1, 2, 3]);
      expect(() => frozen.add(5), throwsUnsupportedError);
    });

    test('frozen by the SDK, not here, is copied — nothing says it is', () {
      final elsewhere = List<int>.unmodifiable([1, 2]);
      expect(identical(frozenList(elsewhere), elsewhere), isFalse);
    });
  });

  group('a set', () {
    test('frozen here is handed on as itself', () {
      final frozen = frozenSet({1, 2});
      expect(identical(frozenSet(frozen), frozen), isTrue);
    });

    test('from outside is copied, and changing it changes nothing', () {
      final outside = {1, 2};
      final frozen = frozenSet(outside);
      expect(identical(frozen, outside), isFalse);
      outside.add(3);
      expect(frozen, {1, 2});
      expect(() => frozen.add(4), throwsUnsupportedError);
    });
  });

  group('a map', () {
    test('frozen here is handed on as itself', () {
      final frozen = frozenMap({'a': 1});
      expect(identical(frozenMap(frozen), frozen), isTrue);
    });

    test('from outside is copied, and changing it changes nothing', () {
      final outside = {'a': 1};
      final frozen = frozenMap(outside);
      expect(identical(frozen, outside), isFalse);
      outside['b'] = 2;
      expect(frozen, {'a': 1});
      expect(() => frozen['c'] = 3, throwsUnsupportedError);
    });
  });

  group('an empty one', () {
    test('is one collection for each type, and frozen', () {
      expect(identical(frozenList(<int>[]), frozenList(<int>[])), isTrue);
      expect(identical(frozenSet(<int>{}), frozenSet(<int>{})), isTrue);
      expect(
        identical(frozenMap(<int, String>{}), frozenMap(<int, String>{})),
        isTrue,
      );
      expect(() => frozenList(<int>[]).add(1), throwsUnsupportedError);
      expect(() => frozenSet(<int>{}).add(1), throwsUnsupportedError);
      expect(() => frozenMap(<int, int>{})[1] = 2, throwsUnsupportedError);
    });

    test('of another type is another', () {
      expect(frozenList(<String>[]), isA<List<String>>());
      expect(frozenSet(<String>{}), isA<Set<String>>());
      expect(frozenMap(<int, String>{}), isA<Map<int, String>>());
      expect(frozenMap(<int, int>{}), isA<Map<int, int>>());
      expect(frozenMap(<String, int>{}), isA<Map<String, int>>());
    });
  });

  // 🚨A mark is this isolate's own, and a file opens on a worker.
  group('🚨frozen in another isolate, as a file opens', () {
    test('is handed on as itself once the model holding it says it is its '
        'own', () async {
      final there = await Isolate.run(() => frozenList([1, 2]));
      expect(
        identical(frozenList(there), there),
        isFalse,
        reason: '⛔premise: the worker\'s mark stayed in the worker',
      );
      expect(identical(frozenList(ownFrozen(there)), there), isTrue);
    });

    test('still refuses a change', () async {
      final (:items, :members, :entries) = await Isolate.run(
        () => (
          items: frozenList([1]),
          members: frozenSet({1}),
          entries: frozenMap({1: 2}),
        ),
      );
      expect(() => ownFrozen(items).add(2), throwsUnsupportedError);
      expect(() => ownFrozen(members).add(2), throwsUnsupportedError);
      expect(() => ownFrozen(entries)[3] = 4, throwsUnsupportedError);
    });
  });

  group('a map a constructor builds from the one it is given', () {
    final one = Object();
    final two = Object();

    test('is the given one when it holds what was built', () {
      final given = frozenMap({'a': one, 'b': two});
      final kept = frozenMapOrSame(given, {'a': one, 'b': two});
      expect(identical(kept, given), isTrue);
    });

    test('is the built one when a value is another object', () {
      final given = frozenMap({'a': one, 'b': two});
      final built = frozenMapOrSame(given, {'a': one, 'b': Object()});
      expect(identical(built, given), isFalse);
      expect(built['a'], same(one));
    });

    test('is the built one when an entry came or went', () {
      final given = frozenMap({'a': one});
      expect(
        identical(frozenMapOrSame(given, {'a': one, 'b': two}), given),
        isFalse,
      );
      expect(
        identical(frozenMapOrSame(given, <String, Object>{}), given),
        isFalse,
      );
    });

    test('is the built one when the same entries stand in another order', () {
      final given = frozenMap({'a': one, 'b': two});
      final built = frozenMapOrSame(given, {'b': two, 'a': one});
      expect(identical(built, given), isFalse);
      expect(built.keys, ['b', 'a']);
    });

    test('is the built one, frozen, when the given one is from outside', () {
      final outside = {'a': one};
      final built = frozenMapOrSame(outside, {'a': one});
      expect(identical(built, outside), isFalse);
      outside['b'] = two;
      expect(built.keys, ['a']);
      expect(identical(frozenMap(built), built), isTrue);
    });

    test('is the built one when nothing was given', () {
      final built = frozenMapOrSame<String, Object>(null, {'a': one});
      expect(built, {'a': one});
      expect(identical(frozenMap(built), built), isTrue);
    });
  });
}
