@TestOn('vm')
library;

import 'dart:io';

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

  group('the sample counts what it learned, not what it tried', () {
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

    test('every candidate is in the order, exactly once', () {
      // ⛔THE PREMISE. An order that quietly dropped candidates would make
      // the runner stop early and report a file as measured.
      final order = spreadOrder(candidates(100));
      expect(order, hasLength(100));
      expect(order.map((m) => m.offset).toSet(), hasLength(100));
    });

    test('a prefix spreads across the file instead of sitting on top', () {
      // 🚨THE FAILURE THIS CATCHES: returning `all` unchanged passes the
      // case above and spends the whole budget in the first function.
      final first = spreadOrder(candidates(100)).take(8).map((m) => m.line);
      expect(
        first.reduce((a, b) => a > b ? a : b),
        greaterThan(50),
        reason: 'the first eight must reach the far half of the file',
      );
    });

    test('the same input gives the same order', () {
      expect(
        spreadOrder(candidates(50)).map((m) => m.offset),
        spreadOrder(candidates(50)).map((m) => m.offset),
      );
    });

    test('a short list survives', () {
      expect(spreadOrder(candidates(1)), hasLength(1));
      expect(spreadOrder(candidates(2)), hasLength(2));
      expect(spreadOrder(const []), isEmpty);
    });

    test('the order opens with the ends, which is where a file forgets', () {
      // ⚠️`sampleOf(all, 1)` is index 0 and `sampleOf(all, 2)` adds the
      // midpoint, so the first entries are the extremes of the spread. A
      // file's last function is the one a top-down walk never reaches.
      final order = spreadOrder(candidates(64));
      expect(order.first.offset, 0);
      expect(order.take(4).map((m) => m.offset), contains(32));
    });
  });

  group('the namer cap', () {
    test('a small set is not capped', () {
      final chosen = namersToRun(['test/services/a_test.dart'], 6);
      expect(chosen, ['test/services/a_test.dart']);
    });

    test('a widget suite goes last even when it is the smallest', () {
      // ⚠️A widget test costs several times a service test. The order is a
      // guess about TIME and never about the verdict — a kill is a kill
      // whichever suite finds it — but across a 339-file campaign it is the
      // difference between minutes and hours.
      //
      // 🚨REAL FILES, AND THE SIZES ARE THE POINT. 🧪The first version of
      // this used invented paths, and a mutation that switched the widget
      // rule off SURVIVED: with no file to measure, every path tied on size
      // and fell through to alphabetical order — where `test/services/`
      // happens to come before `test/ui/` anyway. The rule was unobservable.
      // A small UI file against a large service file separates them.
      const smallUi = 'test/ui/timeline/timeline_scale_test.dart';
      const bigService =
          'test/services/commands/cut_command_coordinator_test.dart';
      expect(File(smallUi).existsSync(), isTrue, reason: 'fixture moved');
      expect(File(bigService).existsSync(), isTrue, reason: 'fixture moved');
      expect(
        File(smallUi).lengthSync(),
        lessThan(File(bigService).lengthSync()),
        reason: 'the premise: without the widget rule, the UI file sorts '
            'FIRST on size, so this test would prove nothing',
      );

      expect(namersToRun([smallUi, bigService], 2), [bigService, smallUi]);
    });

    test('among equals, the smaller suite goes first', () {
      const small = 'test/ui/timeline/timeline_scale_test.dart';
      const big = 'test/ui/brush_canvas_fixture_test.dart';
      expect(File(small).lengthSync(), lessThan(File(big).lengthSync()));
      expect(namersToRun([big, small], 2), [small, big]);
    });

    test('a large set is cut to the cap', () {
      // 🧪`lib/src/models/layer.dart` is named by 305 test files. A survivor
      // there would run every one — a day and a half for one mutation — and
      // the 304th suite says nothing the first six did not.
      final many = [
        for (var i = 0; i < 40; i += 1) 'test/services/f${i}_test.dart',
      ];
      expect(namersToRun(many, 6), hasLength(6));
    });

    test('a cap of zero means no cap', () {
      final many = [
        for (var i = 0; i < 9; i += 1) 'test/services/f${i}_test.dart',
      ];
      expect(namersToRun(many, 0), hasLength(9));
    });
  });

  group('resuming a campaign', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('resume_fx'));
    tearDown(() => dir.deleteSync(recursive: true));

    File out(String contents) =>
        File('${dir.path}/r.jsonl')..writeAsStringSync(contents);

    test('a file with any verdict is done', () {
      final done = filesAlreadyDone(out(
        '{"file":"lib/a.dart","verdict":"killed"}\n'
        '{"file":"lib/b.dart","verdict":"unnamed"}\n',
      ));
      expect(done, {'lib/a.dart', 'lib/b.dart'});
    });

    test('a missing file means nothing is done, not a crash', () {
      expect(filesAlreadyDone(File('${dir.path}/nope.jsonl')), isEmpty);
    });

    test('a truncated last line does not take the resume down', () {
      // 🚨★★★AN INTERRUPT LEAVES EXACTLY THIS. A resume that threw on a half
      // written line would refuse to restart the campaign it was built to
      // restart — and the fix people reach for is deleting the results.
      final done = filesAlreadyDone(out(
        '{"file":"lib/a.dart","verdict":"killed"}\n'
        '{"file":"lib/b.dart","verd',
      ));
      expect(done, contains('lib/a.dart'));
      expect(done, contains('lib/b.dart'));
    });

    test('an empty file is not a done file', () {
      expect(filesAlreadyDone(out('')), isEmpty);
    });
  });
}
