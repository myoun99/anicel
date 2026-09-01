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
  });
}
