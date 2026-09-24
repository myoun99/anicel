import 'dart:math';

import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// deleting-save-compacts-Q1 (유저 2026-09-23): 「한 번에 밀어 내리기 — 떼기
/// 커밋 → 구멍 뒤 살아 있는 바이트를 구멍으로 → 꼬리 자르기」 — chosen over
/// the per-save budget, and then 「전부 재사용으로 … 저장중 크래시만 어떻게
/// 안전책」.
///
/// The plan is pure arithmetic over where the live entries sit, so it is
/// pinned here on numbers; the file it drives is pinned in
/// `a_compaction_packs_the_file_in_place_test` and the crash side in
/// `a_save_that_dies_opens_as_before_or_after_test`.
///
/// 🚨★★★THE CRASH CONTRACT SHAPES BOTH HALVES: a copy may land only on
/// bytes the committed directory does not name — never on its own source
/// (the plan leaves such a span where it is), and never on bytes a move of
/// the same round is leaving (the rounds cut there, and wait for a
/// directory that names the new places).
void main() {
  group('the plan', () {
    test('🎯a file with no holes moves nothing and ends where it ends', () {
      final plan = planAnicelPushDown(const [
        (offset: 0, size: 100),
        (offset: 100, size: 50),
        (offset: 150, size: 30),
      ]);

      expect(plan.moves, isEmpty);
      expect(plan.end, 180);
    });

    test('🎯live bytes behind a hole slide down into it, in file order', () {
      // 100 live, 400 dead, then two live runs.
      final plan = planAnicelPushDown(const [
        (offset: 0, size: 100),
        (offset: 500, size: 60),
        (offset: 560, size: 40),
      ]);

      expect(plan.moves, const [
        (from: 500, to: 100, size: 60),
        (from: 560, to: 160, size: 40),
      ], reason: 'each lands right behind the one before it');
      expect(plan.end, 200, reason: 'the file can end where they end');
    });

    test('🚨a span bigger than the hole in front of it STAYS — its new home '
        'would overlap the bytes the committed directory still names', () {
      // A 20-byte hole in front of a 100-byte run.
      final plan = planAnicelPushDown(const [
        (offset: 0, size: 100),
        (offset: 120, size: 100),
        (offset: 400, size: 50),
      ]);

      expect(
        plan.moves,
        const [(from: 400, to: 220, size: 50)],
        reason: 'the overlapping one stays; the one behind it packs against '
            'it',
      );
      expect(plan.end, 270);
    });

    test('🚨NO BUDGET — everything behind the hole moves in the one save '
        '(유저: 「한 번에」, not 「저장마다 예산(16MB)만큼」)', () {
      const megabyte = 1024 * 1024;
      final live = [
        (offset: 0, size: 10),
        // 200MB of live media behind a 300MB hole: far past the budget the
        // user did not pick.
        for (var i = 0; i < 200; i += 1)
          (offset: 300 * megabyte + i * megabyte, size: megabyte),
      ];

      final plan = planAnicelPushDown(live);

      expect(plan.moves, hasLength(200));
      expect(plan.end, 10 + 200 * megabyte);
    });

    test('🚨the first span moves down to offset zero when what sat there '
        'died', () {
      final plan = planAnicelPushDown(const [(offset: 300, size: 100)]);

      expect(plan.moves, const [(from: 300, to: 0, size: 100)]);
      expect(plan.end, 100);
    });

    test('an empty archive plans nothing and ends at zero', () {
      final plan = planAnicelPushDown(const []);

      expect(plan.moves, isEmpty);
      expect(plan.end, 0);
    });
  });

  group('the rounds', () {
    test('🎯one hole bigger than everything behind it is ONE round', () {
      final plan = planAnicelPushDown(const [
        (offset: 0, size: 10),
        (offset: 1000, size: 100),
        (offset: 1100, size: 100),
        (offset: 1200, size: 100),
      ]);

      expect(anicelCompactionRounds(plan.moves), hasLength(1));
    });

    test('🚨a move that would land on bytes its own round is leaving waits '
        'for the next round', () {
      // Hole 100, then three 100-byte runs: the second one's home is the
      // first one's old place, which stays named until that round commits.
      final plan = planAnicelPushDown(const [
        (offset: 100, size: 100),
        (offset: 200, size: 100),
        (offset: 300, size: 100),
      ]);

      expect(anicelCompactionRounds(plan.moves), const [
        [(from: 100, to: 0, size: 100)],
        [(from: 200, to: 100, size: 100)],
        [(from: 300, to: 200, size: 100)],
      ]);
    });

    test('🚨garbage spread evenly takes rounds that GROW — each directory '
        'frees what the round before it left', () {
      // Every live run followed by a hole of its own size.
      final plan = planAnicelPushDown([
        for (var i = 0; i < 64; i += 1) (offset: 100 + i * 200, size: 100),
      ]);

      final rounds = anicelCompactionRounds(plan.moves);

      expect(
        rounds.length,
        lessThanOrEqualTo(8),
        reason: '64 moves, not 64 rounds: ${rounds.map((r) => r.length)}',
      );
      for (var i = 1; i < rounds.length - 1; i += 1) {
        expect(
          rounds[i].length,
          greaterThanOrEqualTo(rounds[i - 1].length),
          reason: 'round $i: ${rounds.map((r) => r.length)}',
        );
      }
    });

    test('🚨PROPERTY: over random files, no move lands on bytes its own '
        'round vacates, no move lands on its own source, and the rounds '
        'hold every move in order', () {
      final random = Random(20260923);
      for (var file = 0; file < 300; file += 1) {
        final live = <AnicelLiveSpan>[];
        var at = 0;
        for (var i = 0; i < 1 + random.nextInt(40); i += 1) {
          at += random.nextInt(3) == 0 ? 0 : random.nextInt(400);
          final size = 1 + random.nextInt(300);
          live.add((offset: at, size: size));
          at += size;
        }

        final plan = planAnicelPushDown(live);
        final rounds = anicelCompactionRounds(plan.moves);

        expect([for (final round in rounds) ...round], plan.moves);
        for (final round in rounds) {
          for (var i = 0; i < round.length; i += 1) {
            final move = round[i];
            expect(
              move.to + move.size <= move.from,
              isTrue,
              reason: 'file $file: $move overlaps its own source',
            );
            for (var j = 0; j < i; j += 1) {
              final left = round[j];
              final lands = move.to < left.from + left.size &&
                  left.from < move.to + move.size;
              expect(
                lands,
                isFalse,
                reason: 'file $file: $move lands on $left, vacated in the '
                    'same round',
              );
            }
          }
        }
      }
    });
  });
}
