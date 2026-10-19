@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_results.dart';
import '../../tool/test_seconds.dart';

/// 🗣️유저 2026-10-19 (tests-crowd-the-machine-Q4 「결과 캐시 + 불안정 테스트
/// 격리」): a test file already green on this machine with byte-for-byte the
/// same inputs is not run again, and one that went red and then green with
/// the same inputs holds no verdict back until it changes.
///
/// ⚠️WHAT THIS FILE CANNOT REACH: git itself. Spawning it from a test is a
/// process competing with the suite (`tests_do_not_race_the_code_test`), so
/// [contentIds] is handed a git that answers as git does.
void main() {
  String event(Map<String, Object?> fields) => jsonEncode(fields);
  const root = r'C:\repo';

  List<String> suite(int id, String path) => [
    event({
      'type': 'suite',
      'suite': {'id': id, 'path': '$root\\$path'},
      'time': 0,
    }),
  ];
  String start(int test, int suite, int time, {bool hidden = false}) => event({
    'type': 'testStart',
    'test': {'id': test, 'suiteID': suite, 'name': 't$test', 'hidden': hidden},
    'time': time,
  });
  String done(int test, int time, {String result = 'success'}) => event({
    'type': 'testDone',
    'testID': test,
    'result': result,
    'time': time,
  });
  final ended = event({'type': 'done', 'success': true, 'time': 99});

  group('a report', () {
    test('a file whose every test passed is green; one failure or error is '
        'red', () {
      final report = [
        ...suite(0, r'test\a_test.dart'),
        ...suite(1, r'test\b_test.dart'),
        ...suite(2, r'test\c_test.dart'),
        start(1, 0, 10),
        done(1, 20),
        start(2, 1, 10),
        done(2, 30, result: 'failure'),
        start(3, 1, 30),
        done(3, 40),
        // A file that would not load is a hidden test ending in error.
        start(4, 2, 10, hidden: true),
        done(4, 15, result: 'error'),
        ended,
      ].join('\n');
      expect(suiteRuns(report, root: root), [
        (path: 'test/a_test.dart', ms: 10, green: true),
        (path: 'test/b_test.dart', ms: 30, green: false),
        (path: 'test/c_test.dart', ms: 5, green: false),
      ]);
    });

    test('⛔a run that never reached its end says nothing green — its time '
        'still counts', () {
      final report = [
        ...suite(0, r'test\a_test.dart'),
        start(1, 0, 10),
        done(1, 20),
      ].join('\n');
      expect(suiteRuns(report, root: root), [
        (path: 'test/a_test.dart', ms: 10, green: null),
      ]);
    });

    test('⛔a file with a test still open is not green, even in a run that '
        'ended', () {
      final report = [
        ...suite(0, r'test\a_test.dart'),
        start(1, 0, 10),
        done(1, 20),
        start(2, 0, 20),
        ended,
      ].join('\n');
      expect(suiteRuns(report, root: root).single.green, isNull);
    });

    test('the times are read from the same report', () {
      final report = [
        ...suite(0, r'test\a_test.dart'),
        ...suite(1, r'test\b_test.dart'),
        start(1, 0, 10),
        done(1, 25),
        ended,
      ].join('\n');
      expect(timesOf(suiteRuns(report, root: root)), {
        'test/a_test.dart': 15,
      });
    });
  });

  group('the key', () {
    const ids = {'test/a_test.dart': 'aaa', 'lib/x.dart': 'xxx'};
    final key = keyOf(
      ['test/a_test.dart', 'lib/x.dart'],
      ids,
      outside: 'flutter 1',
    );

    test('the same inputs with the same bytes, in any order, are the same '
        'key', () {
      expect(key, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(
        keyOf(['lib/x.dart', 'test/a_test.dart'], ids, outside: 'flutter 1'),
        key,
      );
    });

    test('one byte, one more input, a gone file, or Flutter changing is '
        'another key', () {
      expect(
        keyOf(
          ['test/a_test.dart', 'lib/x.dart'],
          {...ids, 'lib/x.dart': 'xxy'},
          outside: 'flutter 1',
        ),
        isNot(key),
      );
      expect(
        keyOf(
          ['test/a_test.dart', 'lib/x.dart', 'lib/y.dart'],
          {...ids, 'lib/y.dart': 'yyy'},
          outside: 'flutter 1',
        ),
        isNot(key),
      );
      expect(
        keyOf(['test/a_test.dart', 'lib/x.dart'], {
          'test/a_test.dart': 'aaa',
        }, outside: 'flutter 1'),
        isNot(key),
      );
      expect(
        keyOf(['test/a_test.dart', 'lib/x.dart'], ids, outside: 'flutter 2'),
        isNot(key),
      );
    });
  });

  group('the inputs', () {
    final sources = {
      'test/a_test.dart': "import 'helper.dart';",
      'test/helper.dart': "import 'package:anicel/x.dart';\n"
          "final scan = Directory('lib/src/scanned');",
      'lib/x.dart': '',
      'test/flutter_test_config.dart': "import 'package:anicel/c.dart';",
      'lib/c.dart': '',
    };
    final files = [
      ...sources.keys,
      'lib/src/scanned/one.dart',
      'lib/src/scanned/two.png',
      'lib/src/other.dart',
      'assets/fonts/f.ttf',
      'packages/qa_native/src/e.c',
      'pubspec.lock',
    ];
    Inputs inputs() => Inputs(
      imports: {
        'test/a_test.dart': {'test/helper.dart'},
        'test/helper.dart': {'lib/x.dart'},
        'test/flutter_test_config.dart': {'lib/c.dart'},
      },
      files: files,
      read: (path) => sources[path] ?? '',
    );

    test('a test reads itself, what its imports reach, and what any of them '
        'reads as text', () {
      expect(inputs().of('test/a_test.dart'), {
        'test/a_test.dart',
        'test/helper.dart',
        'lib/x.dart',
        'lib/src/scanned/one.dart',
        'lib/src/scanned/two.png',
      });
    });

    test('every test reads the package, its assets, the native package and '
        'the test config with its reach', () {
      expect(inputs().everyTest, {
        'pubspec.yaml',
        'pubspec.lock',
        'dart_test.yaml',
        'test/flutter_test_config.dart',
        'lib/c.dart',
        'assets/fonts/f.ttf',
        'packages/qa_native/src/e.c',
      });
    });
  });

  group('the record', () {
    String? keys(String file) => const {
      'test/a_test.dart': 'k1',
      'test/b_test.dart': 'k2',
      // c's bytes moved since it was kept: a run that could not say what
      // it did leaves the old green where it was, not under the new key.
      'test/c_test.dart': 'k3-now',
    }[file];

    test('a file is still green only under the key it has now', () {
      expect(
        stillGreen(
          ['test/a_test.dart', 'test/b_test.dart', 'test/c_test.dart'],
          {'test/a_test.dart': 'k1', 'test/b_test.dart': 'old'},
          keys,
        ),
        {'test/a_test.dart'},
      );
    });

    test('a run keeps its greens under their keys, drops its reds, and '
        'leaves what it could not say', () {
      expect(
        greensAfter(
          {'test/b_test.dart': 'k2', 'test/c_test.dart': 'k3'},
          [
            (path: 'test/a_test.dart', ms: 1, green: true),
            (path: 'test/b_test.dart', ms: 1, green: false),
            (path: 'test/c_test.dart', ms: 1, green: null),
          ],
          keys,
        ),
        {'test/a_test.dart': 'k1', 'test/c_test.dart': 'k3'},
      );
    });

    test('a red batch is let through only when every file in it was said '
        'and every red one is forgiven', () {
      SuiteRun said(String path, bool? green) =>
          (path: path, ms: 1, green: green);
      bool forgiven(String file) => file == 'test/flaky_test.dart';
      expect(
        holdsVerdictBack([
          said('test/a_test.dart', true),
          said('test/flaky_test.dart', false),
        ], forgiven),
        isFalse,
      );
      expect(
        holdsVerdictBack([
          said('test/flaky_test.dart', false),
          said('test/real_test.dart', false),
        ], forgiven),
        isTrue,
      );
      // ⛔A file the report could not say, a report with nothing in it, or
      // a red batch with no red file in it holds it back.
      expect(
        holdsVerdictBack([
          said('test/flaky_test.dart', false),
          said('test/killed_test.dart', null),
        ], forgiven),
        isTrue,
      );
      expect(holdsVerdictBack(const [], forgiven), isTrue);
      expect(holdsVerdictBack([said('test/a_test.dart', true)], forgiven),
          isTrue);
    });

    test('a flaky file is quarantined until it changes', () {
      const flaky = {'test/a_test.dart': 'own1'};
      bool asNow(String file, String id) => quarantined(file, flaky, {file: id});
      expect(asNow('test/a_test.dart', 'own1'), isTrue);
      expect(asNow('test/a_test.dart', 'own2'), isFalse);
      expect(asNow('test/b_test.dart', 'own1'), isFalse);
    });

    test('the records stand beside the times', () {
      const environment = {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'};
      expect(
        greenRecord(environment)!.path,
        'C:/Users/u/AppData/Local/anicel/test_greens.tsv',
      );
      expect(
        flakyRecord(environment)!.path,
        'C:/Users/u/AppData/Local/anicel/test_flaky.tsv',
      );
      expect(greenRecord(const {}), isNull);
    });
  });

  group('the bytes as they are now', () {
    ProcessResult answer(String stdout, {int exitCode = 0}) =>
        ProcessResult(0, exitCode, stdout, '');

    test('an unchanged file has its index id; a changed or new one is '
        'hashed; a deleted one is gone; nothing outside the inputs is kept',
        () {
      final asked = <List<String>>[];
      final ids = contentIds(
        'C:/repo',
        exists: (path) => path != 'lib/deleted.dart',
        git: (args) {
          asked.add(args);
          return switch (args.first) {
            'ls-files' when args.contains('--stage') => answer([
              '100644 aaa 0\tlib/kept.dart',
              '100644 bbb 0\tlib/changed.dart',
              '100644 ccc 0\tlib/deleted.dart',
              '100644 ddd 0\t단축키/note.txt',
              '',
            ].join('\u0000')),
            'ls-files' => answer([
              'lib/changed.dart',
              'lib/deleted.dart',
              'test/new_test.dart',
              '단축키/other.txt',
              '',
            ].join('\u0000')),
            _ => answer('b2\nn2\n'),
          };
        },
      );
      expect(ids, {
        'lib/kept.dart': 'aaa',
        'lib/changed.dart': 'b2',
        'test/new_test.dart': 'n2',
      });
      expect(asked.last, [
        'hash-object', '--', 'lib/changed.dart', 'test/new_test.dart', //
      ]);
    });

    test('⛔git failing says nothing rather than a part', () {
      expect(
        contentIds(
          'C:/repo',
          exists: (_) => true,
          git: (args) => answer('', exitCode: 128),
        ),
        isNull,
      );
    });

    test('a path a test can read is under lib, test, tool, the assets, the '
        'shaders or the native package — or one every test reads', () {
      expect(canBeAnInput('lib/a.dart'), isTrue);
      expect(canBeAnInput('tool/run.sh'), isTrue);
      expect(canBeAnInput('pubspec.lock'), isTrue);
      expect(canBeAnInput('packages/qa_native/src/e.c'), isTrue);
      expect(canBeAnInput('단축키/a.txt'), isFalse);
      expect(canBeAnInput('README.md'), isFalse);
    });
  });
}
