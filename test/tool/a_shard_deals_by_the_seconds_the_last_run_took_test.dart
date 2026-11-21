@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_shard.dart';

/// 🆕2026-11-17 (card ci-shards-dealt-by-measured-seconds): CI's shards deal
/// their files by the milliseconds each took in the last run that left a
/// record — by size, three times for one that opens the app, only where no
/// run timed it. ↩️By size alone till then (correlated 0.53 with the time;
/// six shards, the longest 31.9 minutes).
void main() {
  group('what a file weighs', () {
    test('a file the last run timed weighs the milliseconds it took, '
        'whatever its size', () {
      expect(
        shardWeights(
          sizes: {'a': 100, 'b': 900000},
          opensTheApp: const {},
          known: {'a': 70000, 'b': 2000},
        ),
        {'a': 70000, 'b': 2000},
      );
    });

    test('a file no run timed weighs its size at the milliseconds a byte '
        'the timed files took — three times its size if it opens the '
        'app', () {
      // 'a' and 'b' took 6000 ms for 3000 bytes (b's 1000 counted three
      // times): 2 ms a byte.
      expect(
        shardWeights(
          sizes: {'a': 0, 'b': 1000, 'new': 500, 'app_new': 500},
          opensTheApp: {'b', 'app_new'},
          known: {'a': 0, 'b': 6000},
        ),
        {'a': 0, 'b': 6000, 'new': 1000, 'app_new': 3000},
      );
    });

    test('with no file timed, a byte weighs one — the size deal as it '
        'was', () {
      expect(
        shardWeights(
          sizes: {'a': 120, 'app': 50},
          opensTheApp: {'app'},
          known: const {},
        ),
        {'a': 120, 'app': 150},
      );
    });

    test('a record of a file that is no longer there weighs nothing', () {
      expect(
        shardWeights(
          sizes: {'a': 10},
          opensTheApp: const {},
          known: {'a': 4000, 'gone': 999999},
        ),
        {'a': 4000},
      );
    });
  });

  group('the deal', () {
    test('every file goes to exactly one shard', () {
      final files = [for (var i = 0; i < 40; i++) 'test/f${i}_test.dart'];
      final weights = {
        for (var i = 0; i < files.length; i++) files[i]: (i * 7919) % 101,
      };
      final shards = shardsOf(files, weights, total: 6);
      expect(shards, hasLength(6));
      expect(
        [for (final shard in shards) ...shard]..sort(),
        [...files]..sort(),
      );
    });

    test('the heaviest go first, each to the lightest shard — the first '
        'such shard on a tie', () {
      expect(
        shardsOf(
          ['a', 'b', 'c', 'd', 'e'],
          {'a': 10, 'b': 50, 'c': 40, 'd': 30, 'e': 20},
          total: 2,
        ),
        [
          ['b', 'e', 'a'],
          ['c', 'd'],
        ],
      );
    });

    test('equal weights go by the files\' order, so every shard that is '
        'given them sorted deals the same piles', () {
      expect(
        shardsOf(
          ['a', 'b', 'c', 'd'],
          {for (final f in 'abcd'.split('')) f: 5},
          total: 2,
        ),
        [
          ['a', 'c'],
          ['b', 'd'],
        ],
      );
    });

    test('dealt again from the same files and weights, the piles are the '
        'same', () {
      final files = [for (var i = 0; i < 25; i++) 'f$i'];
      final weights = {for (final f in files) f: f.length * 3 % 7};
      expect(
        shardsOf(files, Map.of(weights), total: 4),
        shardsOf(
          files,
          Map.fromEntries(weights.entries.toList().reversed),
          total: 4,
        ),
      );
    });

    test('🚨a shard behind before its tests (shard 0\'s analyze, ci.yml) '
        'is dealt that much less — the piles end together', () {
      expect(
        shardsOf(
          ['a', 'b', 'c', 'd', 'e', 'f'],
          {'a': 30, 'b': 30, 'c': 20, 'd': 20, 'e': 10, 'f': 10},
          total: 2,
          behind: {0: 20},
        ),
        // 20 behind + 50 against 70 — and none behind, a c e | b d f.
        [
          ['b', 'd'],
          ['a', 'c', 'e', 'f'],
        ],
      );
    });

    test('behind in milliseconds where a file was timed — and nothing where '
        'none was: the weights are bytes then', () {
      expect(behindInTheDeal({0: 186000}, ['a', 'b'], {'b': 900}), {
        0: 186000,
      });
      expect(behindInTheDeal({0: 186000}, ['a', 'b'], {}), isEmpty);
      expect(
        behindInTheDeal({0: 186000}, ['a'], {'gone': 900}),
        isEmpty,
        reason: 'a record of a file no longer there times none of these',
      );
    });

    test('and every file still goes to exactly one shard', () {
      final files = [for (var i = 0; i < 40; i++) 'test/f${i}_test.dart'];
      final weights = {
        for (var i = 0; i < files.length; i++) files[i]: (i * 7919) % 101,
      };
      final shards = shardsOf(files, weights, total: 6, behind: {0: 300});
      expect(
        [for (final shard in shards) ...shard]..sort(),
        [...files]..sort(),
      );
    });
  });

  group('what a shard hands the next run', () {
    test('its own files\' times and nothing else — not the record it was '
        'seeded with', () {
      expect(
        shardRecord(
          {'mine': 4000, 'seeded': 9000, 'also_mine': 120},
          {'mine', 'also_mine', 'never_timed'},
        ),
        {'mine': 4000, 'also_mine': 120},
      );
    });
  });
}
