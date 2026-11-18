@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show githubWarning;
import '../../tool/test_seconds.dart';
import '../helpers/poll_until.dart';

/// 🆕2026-11-17 (card a-slow-test-cannot-creep): a run says each test that
/// took a minute or more, slowest first — a warning, never a red. Per test,
/// from the report's own testStart → testDone.
void main() {
  String event(Map<String, Object> fields) => jsonEncode(fields);
  const root = r'C:\repo';

  String suite(int id, String path) => event({
    'type': 'suite',
    'suite': {'id': id, 'path': '$root\\$path'},
    'time': 0,
  });
  List<String> run(int id, int suite, String name, int start, [int? end]) => [
    event({
      'type': 'testStart',
      'test': {'id': id, 'suiteID': suite, 'name': name},
      'time': start,
    }),
    if (end != null)
      event({
        'type': 'testDone',
        'testID': id,
        'result': 'success',
        'time': end,
      }),
  ];

  test('a test of a minute or more is said, slowest first, by its file from '
      'the root — not a file\'s load, not one under a minute, not one that '
      'never finished', () {
    final report = [
      suite(0, r'test\a_test.dart'),
      suite(1, r'test\ui\b_test.dart'),
      ...run(1, 0, r'loading C:\repo\test\a_test.dart', 0, 90000),
      ...run(2, 0, 'it waits', 90000, 150000),
      ...run(3, 0, 'it nearly waits', 150000, 209999),
      ...run(4, 1, 'it waits longer', 0, 75000),
      ...run(5, 1, 'it never ends', 75000),
      'not json',
    ].join('\n');
    expect(slowTests(report, root: root), [
      (path: 'test/ui/b_test.dart', name: 'it waits longer', ms: 75000),
      (path: 'test/a_test.dart', name: 'it waits', ms: 60000),
    ]);
  });

  test('the minute is the one a wait for what cannot come costs', () {
    expect(kSlowTest, waitPatience);
  });

  test('on CI it is a warning of the run, on the test\'s file, escaped as '
      'the runner reads it', () {
    expect(
      githubWarning((
        path: 'test/a_test.dart',
        name: '100%: a, b\nc',
        ms: 61400,
      )),
      '::warning file=test/a_test.dart,title=a test of 61 s'
      '::100%25: a, b%0Ac',
    );
    expect(
      githubWarning((path: 'test/a,b:c_test.dart', name: 'x', ms: 60000)),
      '::warning file=test/a%2Cb%3Ac_test.dart,title=a test of 60 s::x',
    );
  });
}
