import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/bake_once_lru.dart';

/// 🚨THE IN-FLIGHT MAP IS THE POINT, NOT THE CACHE.
///
/// Two stores bake into an LRU — the brush stroke previews and the
/// timeline's glyph coverage. A store that only remembers FINISHED work
/// rasterizes the same sample twice under a fast scroll, and the second
/// result overwrites the first while the first's handle is already out
/// with a caller.
void main() {
  test('two asks during one bake share it', () async {
    final lru = BakeOnceLru<String, int>(capacity: 4);
    var bakes = 0;
    final gate = Completer<int>();
    Future<int> bake() {
      bakes += 1;
      return gate.future;
    }

    final first = lru.ensure('a', bake);
    final second = lru.ensure('a', bake);
    expect(bakes, 1, reason: 'the second ask joined the bake in flight');
    gate.complete(7);
    expect(await first, 7);
    expect(await second, 7);
  });

  test('🚨a bake that fails is no answer — the asks while it ran share its '
      'failure, and the next ask bakes anew', () async {
    final lru = BakeOnceLru<String, int>(capacity: 4);
    var bakes = 0;
    final gate = Completer<int>();
    Future<int> slipped() {
      bakes += 1;
      return gate.future;
    }

    final first = lru.ensure('a', slipped);
    final second = lru.ensure('a', slipped);
    gate.completeError(StateError('the GPU slipped'));
    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    expect(bakes, 1, reason: 'one bake while it ran');
    expect(lru.isDone('a'), isFalse);

    final again = await lru.ensure('a', () async {
      bakes += 1;
      return 7;
    });
    expect((again, bakes), (7, 2), reason: 'baked anew');
    expect(lru.peek('a'), 7, reason: 'and kept');
  });

  test('a finished bake answers without baking again', () async {
    final lru = BakeOnceLru<String, int>(capacity: 4);
    var bakes = 0;
    Future<int> bake() async {
      bakes += 1;
      return 1;
    }

    await lru.ensure('a', bake);
    await lru.ensure('a', bake);
    expect(bakes, 1);
    expect(lru.peek('a'), 1);
  });

  test('peek is a miss before anything landed, and never bakes', () {
    final lru = BakeOnceLru<String, int>(capacity: 4);
    expect(lru.peek('a'), isNull);
    expect(lru.length, 0);
  });

  test('past capacity the OLDEST goes, and it is retired', () async {
    final retired = <int>[];
    final lru = BakeOnceLru<String, int>(capacity: 2, retire: retired.add);
    await lru.ensure('a', () async => 1);
    await lru.ensure('b', () async => 2);
    await lru.ensure('c', () async => 3);
    expect(retired, [1], reason: 'the oldest value is handed back to retire');
    expect(lru.peek('a'), isNull);
    expect(lru.peek('b'), 2);
    expect(lru.peek('c'), 3);
  });

  test('🚨what the finished values weigh is told, never bounded: capacity '
      'is how many, however much they weigh (card '
      'census-misses-bake-once-images)', () async {
    final retired = <int>[];
    final lru = BakeOnceLru<String, int>(
      capacity: 2,
      costOf: (weight) => weight,
      retire: retired.add,
    );
    await lru.ensure('a', () async => 1000);
    await lru.ensure('b', () async => 2000);
    expect(retired, isEmpty, reason: 'two at a capacity of two');
    expect(lru.held, 3000);

    await lru.ensure('c', () async => 5);
    expect(retired, [1000], reason: 'the oldest, not the heaviest');
    expect(lru.held, 2005, reason: 'b and c, weighed');
  });

  test('a touch moves an entry off the eviction edge', () async {
    final retired = <int>[];
    final lru = BakeOnceLru<String, int>(capacity: 2, retire: retired.add);
    await lru.ensure('a', () async => 1);
    await lru.ensure('b', () async => 2);
    lru.peek('a');
    await lru.ensure('c', () async => 3);
    expect(retired, [2], reason: 'the touched entry is no longer the oldest');
  });

  test('a null value is a value, not a miss', () async {
    // The glyph store bakes `_BakedGlyph?` — a text that renders to
    // nothing must be REMEMBERED as nothing, or it re-bakes every frame.
    final lru = BakeOnceLru<String, int?>(capacity: 2);
    var bakes = 0;
    await lru.ensure('a', () async {
      bakes += 1;
      return null;
    });
    await lru.ensure('a', () async {
      bakes += 1;
      return null;
    });
    expect(bakes, 1);
  });
}
