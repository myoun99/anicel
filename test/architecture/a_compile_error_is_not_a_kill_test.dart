@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/mutation_run.dart';
import '../../tool/mutations.dart';

/// 🚨★★★THE TWO WAYS A MUTATION RUN LIES TO YOU.
///
/// A mutation run reports 「the suite noticed」 or 「it did not」, and both
/// answers have a impostor:
///
///   · A COMPILE ERROR turns every test red. Read by exit code alone it is
///     indistinguishable from a kill, so a broken edit would be filed as
///     proof that the code is well covered — the exact opposite of the truth.
///   · THE FIRST N MUTATIONS all sit in the first function of the file. A
///     sample taken off the top reports one function's coverage as the whole
///     file's.
///
/// Both are decided by pure functions so they can be driven here, without a
/// suite run. ⚠️The parts that touch the filesystem — refusing a dirty file,
/// restoring in `finally` — are asserted by the tool itself at runtime and
/// exit non-zero; they are not reachable from here without letting a test
/// rewrite `lib/`.
void main() {
  group('a suite that never ran is not a suite that failed', () {
    test('a compile error is UNBUILT, whatever the exit code says', () {
      expect(
        classifyRun(
          exitCode: 1,
          output: 'Failed to load "test/x_test.dart": Compilation failed',
        ),
        Verdict.unbuilt,
      );
    });

    test('a red suite is a kill', () {
      expect(
        classifyRun(
          exitCode: 1,
          output: '00:03 +12 -1: some test [E]\n  Expected: <3>\n  Actual: <4>',
        ),
        Verdict.killed,
      );
    });

    test('a green suite is a survivor', () {
      expect(
        classifyRun(exitCode: 0, output: '00:03 +42: All tests passed!'),
        Verdict.survived,
      );
    });

    test('the word Error inside a failure message is not a compile error', () {
      // ⚠️Tests throw and print errors all the time. Only 「Failed to load」
      // and 「Compilation failed」 mean the file never built, and matching on
      // a bare 「Error」 would file most real kills as unbuilt.
      expect(
        classifyRun(
          exitCode: 1,
          output: '00:01 +0 -1: it works [E]\n  StateError: bad state',
        ),
        Verdict.killed,
      );
    });
  });

  group('the sample is spread, not skimmed', () {
    List<Mutation> candidates(int n) => [
          for (var i = 0; i < n; i += 1)
            Mutation(
              offset: i,
              length: 1,
              was: '<',
              replacement: '<=',
              line: i + 1,
              kind: 'comparison',
            ),
        ];

    test('a small list comes back whole', () {
      expect(sampleOf(candidates(3), 5), hasLength(3));
    });

    test('a big list is thinned to the count asked for', () {
      expect(sampleOf(candidates(100), 5), hasLength(5));
    });

    test('the sample reaches the end of the file, not just the top', () {
      // 🚨THE FAILURE THIS CATCHES: `all.take(5)` passes the two cases above
      // and returns lines 1..5 of a 100-line file every time.
      final picked = sampleOf(candidates(100), 5).map((m) => m.line).toList();
      expect(picked.first, 1);
      expect(picked.last, greaterThan(50));
      for (var i = 1; i < picked.length; i += 1) {
        expect(picked[i], greaterThan(picked[i - 1]));
      }
    });

    test('the same input gives the same sample', () {
      // ⚠️A random sample would make two runs of one file disagree, and there
      // would be no way to tell a real change from the dice.
      expect(
        sampleOf(candidates(100), 7).map((m) => m.offset),
        sampleOf(candidates(100), 7).map((m) => m.offset),
      );
    });

    test('asking for none gives everything rather than nothing', () {
      // ⛔A zero here means 「no limit was set」. Returning an empty list would
      // silently run no mutations and report a clean file.
      expect(sampleOf(candidates(4), 0), hasLength(4));
    });
  });
}
