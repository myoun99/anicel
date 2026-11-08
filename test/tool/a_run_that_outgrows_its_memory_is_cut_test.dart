@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/process_tree.dart';
import '../../tool/test_queue.dart';
import '../helpers/dart_sources.dart';
import '../helpers/poll_until.dart';

ProcessRow row(
  int pid, {
  required int parent,
  int gb = 0,
  int born = 1,
  String name = 'flutter_tester.exe',
}) => (pid: pid, parent: parent, born: born, name: name, bytes: gb << 30);

/// A watch that looks only when it is told to, cutting into [cuts].
MemoryWatch watchOf(List<ProcessRow> Function() read, List<int> cuts) =>
    MemoryWatch(
      100,
      cap: 12 << 30,
      read: read,
      cut: cuts.add,
      every: const Duration(days: 1),
    );

/// 🚨Card a-tester-grew-to-23-gb-and-took-the-desktop-down: the machine's
/// line measured before a launch and nobody looked after it — three testers
/// grew to 22 GB each and the desktop went black. A run is cut when one of
/// its processes passes the cap, and the failure says which.
void main() {
  group('the tree of a run', () {
    test('a process however far down is the run\'s', () {
      final table = [
        row(100, parent: 1, gb: 0, name: 'cmd.exe'),
        row(200, parent: 100, gb: 1, name: 'dart.exe'),
        row(300, parent: 200, gb: 23),
        row(301, parent: 200, gb: 2),
      ];
      expect(largestInTree(table, 100)!.pid, 300);
    });

    test('a process outside it is not', () {
      final table = [
        row(100, parent: 1, gb: 1, name: 'cmd.exe'),
        row(1, parent: 0, gb: 40, name: 'explorer.exe'),
        row(500, parent: 1, gb: 30, name: 'studio64.exe'),
      ];
      expect(largestInTree(table, 100)!.pid, 100);
    });

    test('⚠️a parent number that came round again adopts nobody', () {
      // 500's parent died long ago, and a tester of this run now wears its
      // number: 500 began before that tester did.
      final table = [
        row(100, parent: 1, gb: 1, born: 50, name: 'cmd.exe'),
        row(200, parent: 100, gb: 1, born: 60),
        row(500, parent: 200, gb: 30, born: 10, name: 'studio64.exe'),
      ];
      expect(largestInTree(table, 100)!.pid, isNot(500));
    });

    test('a run not in the table has no answer', () {
      expect(largestInTree([row(1, parent: 0)], 100), isNull);
    });

    test('a loop in the numbers ends', () {
      final table = [
        row(100, parent: 200, gb: 1),
        row(200, parent: 100, gb: 3),
      ];
      expect(largestInTree(table, 100)!.pid, 200);
    });
  });

  group('the watch', () {
    test('a run up to the cap is left alone', () {
      final cuts = <int>[];
      final watch = watchOf(
        () => [
          row(100, parent: 1, name: 'cmd.exe'),
          row(300, parent: 100, gb: 12),
        ],
        cuts,
      );
      addTearDown(watch.stop);
      watch.look();
      expect(cuts, isEmpty);
      expect(watch.outgrew, isNull);
    });

    test('a run past it is cut at its root, and named', () {
      final cuts = <int>[];
      final watch = watchOf(
        () => [
          row(100, parent: 1, name: 'cmd.exe'),
          row(300, parent: 100, gb: 23),
        ],
        cuts,
      );
      addTearDown(watch.stop);
      watch.look();
      expect(cuts, [100]);
      expect(watch.outgrew, contains('flutter_tester.exe'));
      expect(watch.outgrew, contains('pid 300'));
      expect(watch.outgrew, contains('23.0 GB'));
      expect(watch.outgrew, contains('12.0 GB'));
    });

    test('a cut that did not take is asked again', () {
      final cuts = <int>[];
      final watch = watchOf(
        () => [
          row(100, parent: 1, name: 'cmd.exe'),
          row(300, parent: 100, gb: 23),
        ],
        cuts,
      );
      addTearDown(watch.stop);
      watch
        ..look()
        ..look();
      expect(cuts, [100, 100]);
    });

    test('an empty table cuts nothing', () {
      final cuts = <int>[];
      final watch = watchOf(() => const [], cuts);
      addTearDown(watch.stop);
      watch.look();
      expect(cuts, isEmpty);
    });

    test('it looks by itself', () async {
      final cuts = <int>[];
      final watch = MemoryWatch(
        100,
        cap: 12 << 30,
        read: () => [row(100, parent: 1, gb: 23)],
        cut: cuts.add,
        every: const Duration(milliseconds: 1),
      );
      addTearDown(watch.stop);
      expect(await pollUntil(() => cuts.isNotEmpty), isTrue);
      watch.stop();
      final after = cuts.length;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cuts.length, after);
    });
  });

  group("the line's answer", () {
    test('a cut run answers by name, not as it fell', () async {
      final watch = watchOf(() => [row(100, parent: 1, gb: 23)], [])..look();
      expect(await withinMemory(Future.value(1), watch), kOutgrewMemory);
      expect(kOutgrewMemory, isNot(kTimedOut));
    });

    test('a run nothing cut answers for itself', () async {
      final watch = watchOf(() => [row(100, parent: 1, gb: 1)], [])..look();
      expect(await withinMemory(Future.value(3), watch), 3);
    });
  });

  group('the table', () {
    test('this very process is in it, with what it holds', () {
      final table = readProcessTable();
      final me = table.where((row) => row.pid == pid);
      expect(me, hasLength(1));
      // A tester holds far more than a megabyte, and far less than a
      // terabyte: a field read from the wrong offset is neither.
      expect(me.single.bytes, greaterThan(1 << 20));
      expect(me.single.bytes, lessThan(1 << 40));
      expect(me.single.name, isNotEmpty);
      expect(largestInTree(table, pid), isNotNull);
      // Who started it is alive beside it and began first: the numbers the
      // walk stands on, read from the machine.
      final parents = table.where((row) => row.pid == me.single.parent);
      expect(parents, hasLength(1));
      if (Platform.isWindows) {
        expect(me.single.born, greaterThan(0));
        expect(parents.single.born, lessThanOrEqualTo(me.single.born));
      }
    });

    test('what `ps` prints is read, a name with a space and all', () {
      final rows = rowsFromPs(
        '    1     0  2048 init\n'
        '  300     1 10240 flutter tester\n'
        'not a row\n',
      );
      expect(rows, hasLength(2));
      expect(rows.last.pid, 300);
      expect(rows.last.parent, 1);
      expect(rows.last.bytes, 10240 * 1024);
      expect(rows.last.name, 'flutter tester');
    });
  });

  test('⛔every tool that can cut a test run watches its memory', () {
    // The first three by name so a change to any of them reruns this; the
    // walk so a fourth launcher cannot be added without one.
    expect(File('tool/test_queue.dart').existsSync(), isTrue);
    expect(File('tool/affected_tests.dart').existsSync(), isTrue);
    expect(File('tool/mutation_run.dart').existsSync(), isTrue);
    final unwatched = [
      for (final file in dartFilesUnder('tool'))
        if (!file.path.endsWith('process_tree.dart'))
          if (file.readAsStringSync() case final source
              when source.contains('cutTree(') &&
                  !(source.contains('MemoryWatch(') &&
                      source.contains(RegExp(r'\.outgrew|withinMemory\('))))
            file.path,
    ];
    expect(unwatched, isEmpty);
  });
}
