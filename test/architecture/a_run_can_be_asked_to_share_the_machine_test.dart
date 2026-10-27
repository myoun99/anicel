@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show BatchKind, flutterTestArguments, kReporter;

/// 🗣️유저 2026-09-24: 「부하 좀 강도? 낮출수없나. pc가 너무느린데」 — a run
/// of the affected tests can be told how many suites to hold at once, and
/// left alone it asks for nothing new.
void main() {
  test('asked, the run holds that many suites at once', () {
    expect(
      flutterTestArguments(
        ['test/a_test.dart'],
        concurrency: 4,
        kind: BatchKind.crowd,
      ),
      ['test', '--no-pub', kReporter, '--concurrency=4', 'test/a_test.dart'],
    );
  });

  test('not asked, it is the run it always was', () {
    expect(
      flutterTestArguments(['test/a_test.dart'], kind: BatchKind.crowd),
      ['test', '--no-pub', kReporter, 'test/a_test.dart'],
    );
  });

  test('handed a report, it leaves its times there beside the console', () {
    // 2026-10-18: the times `longestFirst` orders the next run by.
    expect(
      flutterTestArguments(
        ['test/a_test.dart'],
        report: 'r.json',
        kind: BatchKind.crowd,
      ),
      [
        'test',
        '--no-pub',
        kReporter,
        '--file-reporter=json:r.json',
        'test/a_test.dart',
      ],
    );
  });
}
