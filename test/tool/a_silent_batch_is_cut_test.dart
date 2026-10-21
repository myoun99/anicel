@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show BatchSilence, finishedByCounter, kSilentBatch, stillRunning;

/// 🗣️유저 2026-10-21, tests-crowd-the-machine-Q17 「15분 동안 끝나는 테스트가
/// 없으면 배치를 끊는다」: a batch that finishes no test for [kSilentBatch] is
/// cut, red, naming the tests still running — two lanes' batches had stood
/// on one never-ending test for hours, one holding nine of eighteen suites.
///
/// ⚠️The cut itself — the timer that looks and the tree it ends — is not
/// reached here: no test may start a process
/// (`tests_do_not_race_the_code_test`). What decides it is.
void main() {
  final t0 = DateTime(2026, 10, 21, 23);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  test('fifteen minutes, as measured', () {
    expect(kSilentBatch, const Duration(minutes: 15));
  });

  test('the counter says how many tests finished — passed, skipped and '
      'failed — the last one in the text', () {
    expect(finishedByCounter('00:03 +42: All tests passed!'), 42);
    expect(finishedByCounter('00:03 +42 ~2 -1: Some tests failed.'), 45);
    expect(finishedByCounter('+1: a\n+9 ~1: b\n+12 ~1 -3: c'), 16);
    expect(finishedByCounter('loading test/a_test.dart'), isNull);
    // A tilde in a test's NAME is not the counter's.
    expect(
      finishedByCounter('+7: shrinks to ~100px under the drop zone'),
      7,
    );
  });

  test('🚨a batch that finishes no test for fifteen minutes is past it — '
      'from its start when it finished none', () {
    final silence = BatchSilence(t0);
    expect(silence.isPast(kSilentBatch, at(14)), isFalse);
    expect(silence.isPast(kSilentBatch, at(15)), isTrue);
  });

  test('a test finishing starts the fifteen minutes again', () {
    final silence = BatchSilence(t0)..heard('00:40 +1: a', at(10));
    expect(silence.isPast(kSilentBatch, at(24)), isFalse);
    expect(silence.isPast(kSilentBatch, at(25)), isTrue);
  });

  test('🚨a test that STARTS is not one finishing — the counter has to move',
      () {
    // flutter prints its counter as each test starts, too: the line that
    // names the test that then never ends carries the same count.
    final silence = BatchSilence(t0)
      ..heard('+3: a finished one', at(1))
      ..heard('+3: the walk that never ends', at(2))
      ..heard('+3: the walk that never ends', at(10));
    expect(silence.isPast(kSilentBatch, at(16)), isTrue);
  });

  test('the cut names the tests started and never finished — not a suite '
      'still loading', () {
    String event(Map<String, Object> e) => jsonEncode({...e, 'time': 0});
    final report = [
      event({
        'type': 'suite',
        'suite': {'id': 1, 'path': r'C:\w\test\ui\a_flip_test.dart'},
      }),
      event({
        'type': 'suite',
        'suite': {'id': 2, 'path': 'C:/w/test/b_test.dart'},
      }),
      event({
        'type': 'testStart',
        'test': {'id': 10, 'suiteID': 1, 'name': 'a finished one'},
      }),
      event({'type': 'testDone', 'testID': 10, 'result': 'success'}),
      event({
        'type': 'testStart',
        'test': {'id': 11, 'suiteID': 1, 'name': 'the walk that never ends'},
      }),
      event({
        'type': 'testStart',
        'test': {
          'id': 12,
          'suiteID': 2,
          'name': 'loading C:/w/test/b_test.dart',
        },
      }),
      'not json',
    ].join('\n');
    expect(stillRunning(report), [
      'C:/w/test/ui/a_flip_test.dart: the walk that never ends',
    ]);
  });
}
