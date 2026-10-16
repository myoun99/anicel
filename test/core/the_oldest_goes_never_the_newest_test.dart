import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/lru.dart';

/// [Lru] — the order a bounded cache lets go by (card
/// every-bounded-cache-is-one-lru): the least recently used first, until
/// what is held is at or under the limit, and never the newest — what was
/// just asked for.
void main() {
  /// An [Lru] over [costs] (kept in their order, so oldest first) with
  /// room for all of them, the letting go written down as it happens —
  /// and the limit, to move.
  ({Lru<String, int> lru, List<String> gone, void Function(int) limitTo})
  holding(Map<String, int> costs) {
    var limit = 1 << 30;
    final gone = <String>[];
    final lru = Lru<String, int>(
      limit: () => limit,
      costOf: (cost) => cost,
      letGo: (key, _) => gone.add(key),
    );
    costs.forEach(lru.keep);
    return (lru: lru, gone: gone, limitTo: (to) => limit = to);
  }

  test('the least recently used goes first — not the largest — and only '
      'until what is held is at the limit', () {
    // 65 held, the limit at 25: the oldest two make it 10. Largest first
    // would have let go of `b` alone.
    final (:lru, :gone, :limitTo) = holding({'a': 5, 'b': 50, 'c': 5, 'd': 5});

    limitTo(25);
    lru.fit();

    expect(gone, ['a', 'b']);
    expect(lru.held, 10);
    expect(lru.keys, ['c', 'd']);
  });

  test('a use makes an entry the newest; a peek does not', () {
    final (:lru, :gone, :limitTo) = holding({'a': 10, 'b': 10, 'c': 10});

    expect(lru.use('a'), 10);
    expect(lru.peek('b'), 10);
    limitTo(20);
    lru.fit();

    expect(gone, ['b'], reason: 'a was used, b only looked at');
    expect(lru.keys, ['c', 'a']);
  });

  test('AT the limit is under it: what got there stops the letting go', () {
    final (:lru, :gone, :limitTo) = holding({'a': 10, 'b': 10, 'c': 10});

    limitTo(20);
    lru.fit();

    expect(gone, ['a'], reason: '20 held is the limit, not past it');
  });

  test('the newest never goes — however much it costs', () {
    final (:lru, :gone, :limitTo) = holding({'a': 10});
    limitTo(50);

    lru.keep('just asked', 100);

    expect(gone, ['a']);
    expect(lru.keys, ['just asked']);
    expect(lru.held, 100, reason: 'still past the limit, and kept');
  });

  test('keeping fits at once; under the limit nothing goes', () {
    final (:lru, :gone, :limitTo) = holding({});
    limitTo(30);

    lru
      ..keep('a', 10)
      ..keep('b', 10);
    expect(gone, isEmpty);

    lru.keep('c', 15);
    expect(gone, ['a']);
    expect(lru.held, 25);
  });

  test('with no cost given it counts entries', () {
    final gone = <String>[];
    final lru = Lru<String, String>(
      limit: () => 2,
      letGo: (key, _) => gone.add(key),
    );

    lru
      ..keep('a', 'A')
      ..keep('b', 'B')
      ..keep('c', 'C');

    expect(gone, ['a']);
    expect(lru.held, 2);
    expect(lru.length, 2);
  });

  test('🚨what is replaced, taken or cleared is NOT let go — it stays the '
      "caller's", () {
    final (:lru, :gone, limitTo: _) = holding({'a': 10, 'b': 20});

    expect(lru.keep('a', 30), 10, reason: 'the value it replaced');
    expect(lru.held, 50, reason: 'its cost went with it');
    expect(lru.take('b'), 20);
    expect(lru.take('nothing'), isNull);
    expect(lru.held, 30);
    lru.clear();

    expect(gone, isEmpty);
    expect(lru.held, 0);
    expect(lru.length, 0);
  });

  test('a null kept is a value, not a miss', () {
    final lru = Lru<String, int?>(limit: () => 2)
      ..keep('nothing', null)
      ..keep('one', 1);

    expect(lru.use('nothing'), isNull);
    expect(lru.containsKey('nothing'), isTrue);
    expect(lru.keys, ['one', 'nothing'], reason: 'the use moved it');
  });
}
