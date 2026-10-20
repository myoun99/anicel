@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show redsOf;
import '../../tool/master_check.dart';
import '../../tool/test_seconds.dart' show SuiteRun;
import '../helpers/temp_dir.dart';

/// 🗣️유저 2026-10-20 (tests-crowd-the-machine-Q8 「나눈다」): what landed on
/// master since the last check is run wide once, and a red is walked back
/// over those landings to the one that made it.
///
/// ⚠️WHAT THIS FILE CANNOT REACH: git, the lane it moves and the runs it
/// starts. Spawning them from a test is a process competing with the suite
/// (`tests_do_not_race_the_code_test`), so the walk is handed a run that
/// answers from a table.
void main() {
  group('the landings', () {
    const reflog =
        'c5\tmerge work/fold-the-groups: Fast-forward\n'
        'c3\tmerge work/steady-line: Fast-forward\n'
        'c1\tmerge work/old-name: Fast-forward\n'
        'c1\tmerge work/older-name: Fast-forward\n';

    test('a landing is a commit the reflog says a lane left master at', () {
      expect(landingsIn(['c1', 'c2', 'c3', 'c4', 'c5'], reflog), [
        (sha: 'c1', name: 'old-name'),
        (sha: 'c3', name: 'steady-line'),
        (sha: 'c5', name: 'fold-the-groups'),
      ]);
    });

    test('the last commit is a landing even when no lane named it', () {
      expect(landingsIn(['c6', 'c7'], reflog), [(sha: 'c7', name: 'master')]);
    });

    test("a subject that names no lane is the landing's name", () {
      expect(laneOf('merge work/corners-and-fold: Fast-forward'),
          'corners-and-fold');
      expect(laneOf('pull: Fast-forward'), 'pull: Fast-forward');
    });
  });

  group('the walk', () {
    // Each file → the first landing it is red at.
    const redFrom = {'a': 3, 'b': 1, 'c': 7, 'd': 0};
    late List<int> asked;

    Future<Map<String, int>> walk(Set<String> reds, int count) {
      asked = [];
      return culprits(reds, count, (landing, files) async {
        asked.add(landing);
        return {
          for (final file in files)
            if (redFrom[file]! <= landing) file,
        };
      });
    }

    test('each red is put on the first landing it is red at', () async {
      expect(await walk({'a', 'b', 'c', 'd'}, 8), redFrom);
    });

    test('reds the same landings made are walked together', () async {
      await walk({'a'}, 8);
      final alone = asked.length;
      await walk({'a', 'b', 'c', 'd'}, 8);
      expect(alone, 3);
      expect(asked.length, lessThan(4 * alone));
    });

    test('a red at the only landing asks nothing', () async {
      expect(await walk({'d'}, 1), {'d': 0});
      expect(asked, isEmpty);
    });

    test('⛔no red, no run', () async {
      expect(await walk({}, 8), isEmpty);
      expect(asked, isEmpty);
    });
  });

  group('the records', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('master_fx'));
    tearDown(() => deleteTempQuietly(folder));

    test('a check with no red is green; one with a red keeps the green '
        'before it', () {
      final records = MasterRecords(folder.path);
      expect(records.checked, isNull);
      expect(records.green, isNull);

      records.keep(checked: 'm1', reds: {});
      expect((records.checked, records.green), ('m1', 'm1'));

      records.keep(
        checked: 'm2',
        reds: {'test/a_test.dart': (sha: 'm2', name: 'fold-the-groups')},
      );
      expect((records.checked, records.green), ('m2', 'm1'));
      expect(records.reds, {
        'test/a_test.dart': (sha: 'm2', name: 'fold-the-groups'),
      });

      records.keep(checked: 'm3', reds: {});
      expect((records.checked, records.green), ('m3', 'm3'));
      expect(records.reds, isEmpty);
    });

    test('a miss is added to those before it', () {
      MasterRecords(folder.path)
        ..noteMisses({'m2 test/a_test.dart': '3'})
        ..noteMisses({'m4 test/b_test.dart': '-'});
      expect(MasterRecords(folder.path).misses, {
        'm2 test/a_test.dart': '3',
        'm4 test/b_test.dart': '-',
      });
    });
  });

  group("what a run's reds say", () {
    SuiteRun run(String path, bool? green) =>
        (path: path, ms: 1, green: green);
    final batches = {
      0: [run('test/b_test.dart', false), run('test/ok_test.dart', true)],
      1: [run('test/flaky_test.dart', false), run('test/a_test.dart', false)],
    };

    test('every red but those set aside, in order', () {
      expect(
        redsOf(batches, [0, 1], (file) => file == 'test/flaky_test.dart'),
        ['test/a_test.dart', 'test/b_test.dart'],
      );
    });

    test('⛔a red batch that did not say what each file did says nothing', () {
      expect(
        redsOf({
          ...batches,
          2: [run('test/c_test.dart', null)],
        }, [0, 1, 2], (_) => false),
        isNull,
      );
      expect(redsOf(batches, [0, 1, 3], (_) => false), isNull);
    });
  });

  test("a red on master holds a lane back only when the lane doesn't carry "
      'the landing that made it', () {
    const made = (sha: 'm2', name: 'fold-the-groups');
    final reds = {'test/a_test.dart': made};
    expect(redOnMaster('test/a_test.dart', reds, (sha) => sha == 'm2'), made);
    expect(redOnMaster('test/a_test.dart', reds, (_) => false), isNull);
    expect(redOnMaster('test/b_test.dart', reds, (_) => true), isNull);
  });

  test('a red stands as many imports from the change as its reach needs', () {
    const imports = {
      'test/a_test.dart': {'test/helper.dart'},
      'test/helper.dart': {'lib/x.dart'},
      'lib/x.dart': {'lib/y.dart'},
    };
    const texts = {'test/helper.dart': "File('tool/lane.sh')"};
    int? away(Set<String> changed) => importsAway(
      'test/a_test.dart',
      changed,
      imports,
      (path) => texts[path] ?? '',
    );
    expect(away({'test/a_test.dart'}), 0);
    expect(away({'tool/lane.sh'}), 1);
    expect(away({'lib/x.dart'}), 2);
    expect(away({'lib/y.dart'}), 3);
    expect(away({'lib/z.dart'}), isNull);
  });
}
