@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/process_tree.dart';

ProcessRow row(int pid, {required int parent, int born = 1, String? name}) => (
  pid: pid,
  parent: parent,
  born: born,
  name: name ?? 'flutter_tester',
  bytes: 0,
  cpu: 0,
);

/// 🚨A CUT ENDS EVERY PROCESS UNDER WHAT IT CUTS, ON EVERY OS, BY ONE WALK
/// (관제 2026-11-24 12:1x, card release-2026-11-24). Linux's cut took the
/// shell's own children alone (`pkill -P`), and every batch PR 1503 and 1504
/// cut for its silence left its two testers running beside the files run
/// again to tell whose the stop was. The suite starts no process, so the
/// walk is pinned on a table it is handed, and on the machine's own from
/// this tester up.
void main() {
  // `flutter test` → its tool → two testers, one of which started another;
  // and a process beside them that is not the run's.
  final table = [
    row(100, parent: 1, name: 'flutter'),
    row(200, parent: 100, name: 'dart'),
    row(300, parent: 200),
    row(301, parent: 200),
    row(500, parent: 300, name: 'helper'),
    row(400, parent: 1, name: 'beside'),
  ];

  test('🚨the cut ends every process under it, of one look, the top first, '
      'and returns them — what lies three down too', () {
    var looks = 0;
    final ended = <int>[];
    final cut = cutTree(
      100,
      read: () {
        looks += 1;
        return table;
      },
      end: ended.add,
    );
    expect(looks, 1);
    expect(ended.first, 100);
    expect(ended.toSet(), {100, 200, 300, 301, 500});
    expect(ended, hasLength(5), reason: 'each once');
    // A parent before its children, so none is left to init by an end
    // that came before it was looked for.
    const below = [(200, 100), (300, 200), (301, 200), (500, 300)];
    for (final (child, parent) in below) {
      expect(ended.indexOf(parent), lessThan(ended.indexOf(child)));
    }
    expect({for (final row in cut) row.pid}, {100, 200, 300, 301, 500});
  });

  test('a table that cannot be read still ends what was cut', () {
    final ended = <int>[];
    expect(cutTree(100, read: () => const [], end: ended.add), isEmpty);
    expect(ended, [100]);
  });

  test('🚨what still runs after a cut is named — a number given again to '
      'another process is not it', () async {
    final cut = cutTree(100, read: () => table, end: (_) {});
    final looks = [
      // The first look still finds a tester, and the helper's number held
      // by a process started since; the second, nothing of the cut.
      [row(301, parent: 1), row(500, parent: 1, born: 9, name: 'helper')],
      <ProcessRow>[],
    ];
    var look = 0;
    final left = await stillStanding(
      cut,
      read: () => looks[look++],
      looks: 3,
      every: Duration.zero,
    );
    expect(left, isEmpty);
    expect(look, 2, reason: 'no look once nothing is left');
    final stood = await stillStanding(
      cut,
      read: () => [row(301, parent: 1)],
      looks: 2,
      every: Duration.zero,
    );
    expect([for (final row in stood) row.pid], [301]);
    final again = await stillStanding(
      cut,
      read: () => [row(500, parent: 1, born: 9, name: 'helper')],
      looks: 1,
    );
    expect(again, isEmpty, reason: 'the number is another process\'s now');
  });

  test('a cut says how many it ended, by name, and what of them still runs',
      () {
    final cut = cutTree(100, read: () => table, end: (_) {});
    expect(
      cutSaid(cut, const []),
      'the cut ended 5 process(es) (flutter ×1 · dart ×1 · flutter_tester '
      '×2 · helper ×1) — none still runs',
    );
    expect(
      cutSaid(cut, [row(301, parent: 1)]),
      '🚨 the cut ended 5 process(es) (flutter ×1 · dart ×1 · flutter_tester '
      '×2 · helper ×1) — still running: flutter_tester 301',
    );
  });

  test('🚨on the machine\'s own table the walk reaches this tester from '
      'each process above it — two and more down, as `taskkill /T` took '
      'them', () {
    // Windows' table and `taskkill /T` read the same parent of each
    // process, the one the snapshot of the system's processes names
    // (TH32CS_SNAPPROCESS); off Windows `ps` names it.
    final machine = readProcessTable();
    final byPid = {for (final row in machine) row.pid: row};
    expect(byPid[pid], isNotNull);
    var above = byPid[pid]!.parent;
    var levels = 0;
    while (levels < 3) {
      final up = byPid[above];
      if (up == null || up.pid == up.parent) break;
      expect(
        [for (final row in treeIn(machine, above)) row.pid],
        contains(pid),
        reason: '${up.name} ($above), $levels above this tester\'s parent',
      );
      above = up.parent;
      levels += 1;
    }
    expect(levels, greaterThanOrEqualTo(2), reason: 'a tester runs two down');
  });

  test('⛔no OS walks its own way: the cut asks no tool of the OS', () {
    final source = File('tool/process_tree.dart').readAsStringSync();
    expect(source, isNot(contains("'taskkill'")));
    expect(source, isNot(contains("'pkill'")));
  });
}
