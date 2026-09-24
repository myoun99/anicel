@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show lastSkipCount;

/// 🚨★★★A SKIP IS NOT A PASS.
///
/// `flutter test` ends with `00:03 +42 ~2: All tests passed!`. The tilde is
/// two tests that did not run, and the sentence beside it says passed. In
/// this repo the usual cause is a missing native engine: without
/// `build/native_standalone`, every parity pin between the C kernel and the
/// Dart reference becomes an empty stub with a `skip:` reason.
///
/// 🧪THIS EXISTS BECAUSE KNOWING WAS NOT ENOUGH. The memory file
/// `affected-tests-not-full-suite.md` has said so since 2026-08-28 and told
/// the reader to count the tildes; the fix — two `cmake` lines — is one
/// paragraph further down it. On 2026-09-01 that line was read, `~2` was
/// seen, 「a known local condition」 was written, and the run carried on. A
/// rule that has to be remembered every time is a missing mechanism, so
/// `affected_tests` now says it out loud with the command attached.
///
/// ⚠️`test/architecture/` and not `test/tool/`: the pre-push hook treats
/// `test/tool/` as board-only and pushes it to master without a PR.
void main() {
  group('reading the counter', () {
    test('a tilde is a skip count', () {
      expect(lastSkipCount('00:03 +42 ~2: All tests passed!'), 2);
    });

    test('no tilde means nothing was skipped', () {
      // ⛔Null rather than 0, so a caller can tell 「this chunk said nothing
      // about skips」 from 「this chunk said zero」. The stream arrives in
      // pieces and most of them mention neither.
      expect(lastSkipCount('00:03 +42: All tests passed!'), isNull);
      expect(lastSkipCount(''), isNull);
    });

    test('the LAST count wins, because the counter is cumulative', () {
      // 🚨THE FAILURE THIS CATCHES: taking the first match reports the skip
      // total as whatever it was a few tests in — usually 1 — and a run that
      // skipped sixteen would be reported as having skipped one.
      expect(
        lastSkipCount('+1 ~1: a\n+9 ~7: b\n+40 ~16: All tests passed!'),
        16,
      );
    });

    test('a number that is not a skip count is not read as one', () {
      // The passed counter, the clock and the failure counter all sit on the
      // same line. Only the tilde marks a skip.
      expect(lastSkipCount('00:03 +42 -1: Some tests failed.'), isNull);
    });

    test('a many-digit count is read whole', () {
      expect(lastSkipCount('+900 ~123: All tests passed!'), 123);
    });

    test('🚨a count after a failure is still read', () {
      // 2026-09-23: a whole-suite gate skipped 22 and said 「12 test(s)
      // SKIPPED」. Once a test fails the counter grows a `-<failed>`, and
      // the pattern stopped matching there — every skip after the first
      // red went unsaid.
      expect(lastSkipCount('17:38 +12113 ~22 -1: Some tests failed.'), 22);
      expect(
        lastSkipCount('+100 ~12: a\n+6310 ~12 -1: b\n+12113 ~22 -1: c'),
        22,
        reason: 'the counter is cumulative across the failure too',
      );
    });

    /// 🚨★★★**A TILDE IN A TEST NAME IS NOT A SKIP COUNT.** 실측
    /// 2026-09-08: a run reported 「105 test(s) SKIPPED」 where five had
    /// been, because one of the tests it printed is called 「a bare Row
    /// overflowed at the ~100px a drop-zone preview shrinks to」 and the
    /// pattern was a bare `~(\d+)`.
    ///
    /// ⛔That is this gate crying wolf, which is worse than it staying
    /// quiet: the next reader learns to wave a skip warning through, and
    /// the whole point of the file is that a warning nobody obeys is not a
    /// mechanism.
    test('a tilde inside a test NAME is not the counter', () {
      expect(
        lastSkipCount(
          '00:06 +633 -1: some_test.dart: a bare Row overflowed at the '
          '~100px a drop-zone preview shrinks to',
        ),
        isNull,
      );
      expect(
        lastSkipCount(
          '00:01 +5 ~2: a.dart: passed\n'
          '00:06 +633 -1: b.dart: overflowed at the ~100px it shrinks to',
        ),
        2,
        reason: 'the real counter still wins, and a later name cannot '
            'overwrite it',
      );
    });
  });
}
