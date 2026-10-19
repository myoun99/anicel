@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_seconds.dart';

/// 🆕2026-10-18 (card tests-crowd-the-machine): a batch ends when its
/// slowest file ends, so `affected_tests` hands its files out longest first,
/// by the times this machine's earlier runs left — 60 timeline files at four
/// at a time took 205s where their work was 174s a slot, because the 75s
/// file started near the end and ran alone.
void main() {
  group('longest first', () {
    test('the longer a file took, the earlier it goes', () {
      expect(
        longestFirst(
          ['a_test.dart', 'b_test.dart', 'c_test.dart'],
          {'a_test.dart': 10, 'b_test.dart': 75000, 'c_test.dart': 4000},
        ),
        ['b_test.dart', 'c_test.dart', 'a_test.dart'],
      );
    });

    test('a file never timed goes ahead of every timed one', () {
      expect(
        longestFirst(['a_test.dart', 'new_test.dart'], {'a_test.dart': 9}),
        ['new_test.dart', 'a_test.dart'],
      );
    });

    test('equal times keep the order they came in', () {
      expect(
        longestFirst(['z_test.dart', 'a_test.dart'], const {}),
        ['z_test.dart', 'a_test.dart'],
      );
    });
  });

  group("a batch's report", () {
    String event(Map<String, Object> e) => jsonEncode(e);
    const root = r'C:\repo\lane';

    test('a file takes from its loading to its last test, keyed from the '
        'root with /', () {
      final report = [
        event({
          'type': 'suite',
          'suite': {'id': 0, 'path': r'C:\repo\lane\test\ui\a_test.dart'},
          'time': 5,
        }),
        event({
          'type': 'testStart',
          'test': {'id': 1, 'suiteID': 0, 'name': 'loading a_test.dart'},
          'time': 100,
        }),
        event({'type': 'testDone', 'testID': 1, 'time': 900}),
        event({
          'type': 'testStart',
          'test': {'id': 2, 'suiteID': 0, 'name': 'it draws'},
          'time': 900,
        }),
        event({'type': 'testDone', 'testID': 2, 'time': 4100}),
        'not json at all',
      ].join('\n');
      expect(timesOf(suiteRuns(report, root: root)), {
        'test/ui/a_test.dart': 4000,
      });
    });

    test("a root spelled in another case is the same root — Windows' drive "
        'letter', () {
      final report = [
        event({
          'type': 'suite',
          'suite': {'id': 0, 'path': r'C:\repo\lane\test\a_test.dart'},
          'time': 0,
        }),
        event({
          'type': 'testStart',
          'test': {'id': 1, 'suiteID': 0, 'name': 'it draws'},
          'time': 10,
        }),
        event({'type': 'testDone', 'testID': 1, 'time': 30}),
      ].join('\n');
      expect(timesOf(suiteRuns(report, root: r'c:\repo\lane')), {
        'test/a_test.dart': 20,
      });
    });

    test('⛔a file that never started a test has no time', () {
      final report = event({
        'type': 'suite',
        'suite': {'id': 0, 'path': r'C:\repo\lane\test\b_test.dart'},
        'time': 5,
      });
      expect(timesOf(suiteRuns(report, root: root)), isEmpty);
    });
  });

  group('the record', () {
    test('reads what it writes, sorted, and skips a line that is not one', () {
      final text = writePairs({'b_test.dart': 2, 'a_test.dart': 1});
      expect(text, 'a_test.dart\t1\nb_test.dart\t2\n');
      expect(readTimes('${text}half a line\nc_test.dart\tx\n'), {
        'a_test.dart': 1,
        'b_test.dart': 2,
      });
    });

    test('a file measured again keeps the mean of the two', () {
      expect(
        merged({'a_test.dart': 1000, 'b_test.dart': 7}, {'a_test.dart': 3000}),
        {'a_test.dart': 2000, 'b_test.dart': 7},
      );
      expect(merged(const {}, {'n_test.dart': 5}), {'n_test.dart': 5});
    });
  });

  group("the machine's folder", () {
    test("Windows' local app data, else the cache folder, else none", () {
      expect(
        machineCacheFolder({'LOCALAPPDATA': r'C:\Users\u\AppData\Local'}),
        'C:/Users/u/AppData/Local/anicel',
      );
      expect(
        machineCacheFolder({'XDG_CACHE_HOME': '/c', 'HOME': '/h'}),
        '/c/anicel',
      );
      expect(machineCacheFolder({'HOME': '/h'}), '/h/.cache/anicel');
      expect(machineCacheFolder(const {}), isNull);
    });

    test('⛔the same folder tool/run.sh builds its exes under', () {
      // Two spellings of one place (this file and the launcher's shell):
      // change both or neither.
      final launcher = File('tool/run.sh').readAsStringSync();
      expect(launcher, contains(r'CACHE="${LOCALAPPDATA//\\//}/anicel/tools"'));
      expect(
        launcher,
        contains(r'CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/anicel/tools"'),
      );
    });
  });
}
