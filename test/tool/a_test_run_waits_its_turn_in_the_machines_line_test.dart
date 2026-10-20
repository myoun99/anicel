@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_queue.dart';
import '../../tool/test_seconds.dart' show kUntimedFileMs;
import '../helpers/temp_dir.dart';

/// A file by its name alone: Windows lists a folder with `\`, and the
/// paths these tests build use `/`.
String nameOf(File file) => file.uri.pathSegments.last;

/// 🗣️유저 2026-10-18 (tests-crowd-the-machine-Q1 「b」 — 「②기계 하나의 테스트
/// 대기열」) · 10-19 (「일일이 감시로 손으로 확인하는거말고 ci로해서 자원
/// 안쓰게」 · 「최대가 10만되게 할수있나. 지금상태면 단독진행일때
/// 5개제한이잖아」 · Q3 「짧은 실행은 틈에 끼운다」) · 10-20 (Q6 「전부」 —
/// 「작은실행은 순서 앞당긴다거나 … 다 싹 개선해줘」): the machine's test runs
/// stand in one line, hold ten suites between them — all ten for a run
/// alone, five each beside another — the shortest and longest-waiting
/// first, others in the gaps the first leaves, and a run that waits
/// launches nothing.
///
/// ⚠️WHAT THIS FILE CANNOT REACH: a ticket held by a DIFFERENT live process,
/// and two processes deciding under the line's lock at once. Both need a
/// second process, which this corpus forbids
/// (`tests_do_not_race_the_code_test`), and POSIX locks belong to the
/// process, so one taken here is re-takeable here. Which tickets are held
/// is therefore handed in ([inTurn]'s `ended`), and the probe itself is
/// pinned only for a ticket nobody holds — as
/// `a_run_that_ended_leaves_its_room_test` pins the same law for the app's
/// rooms.
void main() {
  // The moment every line below is decided at.
  final t0 = DateTime(2026, 10, 20, 14);
  DateTime ago(int seconds) => t0.subtract(Duration(seconds: seconds));
  Standing waiting(String name, {int? files, int? work, int waited = 0}) => (
    name: name,
    suites: null,
    files: files,
    work: work,
    since: ago(waited),
  );
  Standing runningAt(
    String name,
    int suites, {
    int? files,
    int? work,
    int ran = 0,
  }) => (name: name, suites: suites, files: files, work: work, since: ago(ran));
  int? decide(String mine, List<Standing> line, {int? asked}) =>
      suitesToRun(mine, line, asked: asked, now: t0);
  List<String> turnOrder(List<Standing> line) => [
    for (final s in waitingInTurn(line, t0)) s.name,
  ];

  group('the line', () {
    test('a ticket asked for earlier sorts first, and says when it was asked',
        () {
      final names = [
        ticketName(1000000000000, 7),
        ticketName(40, 1),
        ticketName(5, 99),
      ]..sort();
      expect(names, [
        ticketName(5, 99),
        ticketName(40, 1),
        ticketName(1000000000000, 7),
      ]);
      expect(
        askedAt(ticketName(1000000000000, 7)),
        DateTime.fromMicrosecondsSinceEpoch(1000000000000),
      );
      expect(askedAt('deciding.lock'), isNull);
    });

    test('ten suites between every run; half each when two share', () {
      expect(kMachineSuites, 10);
      expect(kSharedSuites, 5);
    });

    test('a run alone in the line takes the machine — or what it asked for',
        () {
      expect(decide('a', [waiting('a')]), 10);
      expect(decide('a', [waiting('a')], asked: 4), 4);
      expect(decide('a', [waiting('a')], asked: 20), 10);
    });

    test('with another long run in line, ahead or behind, a run takes half',
        () {
      expect(decide('a', [waiting('a'), waiting('b')]), 5);
      expect(decide('b', [runningAt('a', 5), waiting('b')]), 5);
    });

    test('⛔a run holding all ten is waited out, not joined', () {
      expect(decide('b', [runningAt('a', 10), waiting('b')]), isNull);
      // …though one that asked for fewer leaves the rest.
      expect(decide('b', [runningAt('a', 3), waiting('b')]), 5);
    });

    test('⛔a third waits while two hold the ten, and a run not in line '
        'takes nothing', () {
      expect(
        decide('c', [runningAt('a', 5), runningAt('b', 5), waiting('c')]),
        isNull,
      );
      expect(decide('gone', [waiting('a')]), isNull);
    });

    test('a run is charged no more suites than the files it names', () {
      expect(decide('a', [waiting('a', files: 1)]), 1);
      expect(decide('a', [waiting('a', files: 2)], asked: 1), 1);
      // A long run's last batch of three takes three.
      expect(decide('a', [waiting('a', files: 3)]), 3);
    });

    test('of runs that waited alike, the shortest is first in line — and the '
        'longer does not start on what the first would leave it', () {
      final line = [
        waiting('long', work: 3600, waited: 60),
        waiting('short', work: 300, waited: 60),
      ];
      expect(turnOrder(line), ['short', 'long']);
      expect(decide('short', line), 5);
      expect(decide('long', line), isNull);
    });

    test('a long run comes forward as it waits, so none waits for ever', () {
      final line = [
        waiting('long', work: 3600, waited: 3600),
        waiting('short', work: 300, waited: 60),
      ];
      expect(turnOrder(line), ['long', 'short']);
      expect(decide('long', line), 10);
      expect(decide('short', line), isNull);
    });

    test('runs alike keep the order they asked in', () {
      expect(turnOrder([waiting('b', waited: 10), waiting('a', waited: 5)]), [
        'b', 'a', //
      ]);
      expect(turnOrder([waiting('b'), waiting('a')]), ['a', 'b']);
    });

    test('a run that did not say since when it waits stands from when its '
        'ticket was asked', () {
      final name = ticketName(ago(100).microsecondsSinceEpoch, 1);
      Standing unsaid() =>
          (name: name, suites: null, files: null, work: null, since: null);
      expect(turnOrder([waiting('a', waited: 50), unsaid()]), [name, 'a']);
      expect(turnOrder([waiting('a', waited: 200), unsaid()]), ['a', name]);
    });

    test('beside the first in line a run starts when both fit now — and '
        'waits when it would take the first its suites', () {
      expect(decide('b', [waiting('a'), waiting('b')]), 5);
      final line = [runningAt('r', 2), waiting('a'), waiting('b')];
      expect(decide('a', line), 5);
      expect(decide('b', line), isNull);
    });

    test('while the first cannot start, a run takes the gap if it ends before '
        'the running runs leave the first its suites', () {
      final line = [
        // Ends in 600s, and in 100s.
        runningAt('r', 5, work: 3000),
        runningAt('q', 3, work: 300),
        waiting('first', waited: 1000),
        waiting('s', files: 2, work: 60),
        waiting('s2', files: 2, work: 400),
      ];
      expect(turnOrder(line).first, 'first');
      expect(decide('first', line), isNull);
      // 30s, in the gap of 100s.
      expect(decide('s', line), 2);
      // 200s would hold the first back.
      expect(decide('s2', line), isNull);
    });

    test('…or if it fits in what they leave over beyond the first', () {
      final line = [
        // Ends in 600s, and in 100s with one suite to spare.
        runningAt('r', 4, work: 2400),
        runningAt('q', 4, work: 400),
        waiting('first', waited: 1000),
        waiting('s1', files: 1, work: 400),
        waiting('s2', files: 2, work: 400),
      ];
      expect(turnOrder(line).first, 'first');
      expect(decide('s1', line), 1);
      expect(decide('s2', line), isNull);
    });

    test('while the line cannot tell when the first will start, only a quick '
        'run takes the gap', () {
      for (final unsaid in <Standing>[
        runningAt('r', 8),
        (name: 'r', suites: 8, files: null, work: 800, since: null),
      ]) {
        final line = [
          unsaid,
          waiting('first', waited: 60),
          waiting('quick', files: 2, work: 240),
          waiting('slow', files: 2, work: 242),
        ];
        expect(turnOrder(line).first, 'first');
        expect(decide('quick', line), 2);
        expect(decide('slow', line), isNull);
      }
    });

    test('⛔a running run past its end leaves no gap to wait in', () {
      final line = [
        runningAt('r', 8, work: 400, ran: 1000),
        waiting('first', waited: 60),
        waiting('s', files: 2, work: 60),
      ];
      expect(decide('s', line), isNull);
      // The same run with 50s still to go leaves 30s of gap room.
      line[0] = runningAt('r', 8, work: 400);
      expect(decide('s', line), 2);
    });

    test('⛔small runs do not halve a long run — it waits them out and takes '
        'the machine', () {
      expect(
        decide('a', [waiting('a'), runningAt('s', 1, files: 1, work: 600)]),
        isNull,
      );
      expect(
        decide('a', [
          waiting('a'),
          runningAt('s', 1, files: 1, work: 600),
        ], asked: 9),
        9,
      );
      // One machine-second more is a long run.
      expect(
        decide('a', [waiting('a'), runningAt('s', 1, files: 1, work: 601)]),
        5,
      );
    });

    test('a run that cannot say its work is a long one: an hour of one '
        "suite's time", () {
      expect(
        decide('a', [waiting('a'), runningAt('s', 1, files: 1)]),
        5,
      );
      expect(
        turnOrder([
          waiting('u', waited: 100),
          waiting('k', work: 3599, waited: 100),
        ]),
        ['k', 'u'],
      );
      expect(
        turnOrder([
          waiting('u', waited: 100),
          waiting('k', work: 3601, waited: 100),
        ]),
        ['u', 'k'],
      );
    });

    test('the line stands in the machine folder the test times are kept in',
        () {
      expect(
        queueFolder({'LOCALAPPDATA': r'C:\Users\u\AppData\Local'})!.path,
        'C:/Users/u/AppData/Local/anicel/test_queue',
      );
      expect(queueFolder(const {}), isNull);
    });
  });

  group('a command', () {
    test('a flutter test says how many suites it asks for, in any spelling',
        () {
      expect(askedSuites(['flutter', 'test', 'a_test.dart']), isNull);
      expect(askedSuites(['flutter', 'test', '-j', '2']), 2);
      expect(askedSuites(['flutter', 'test', '-j12', '--no-pub']), 12);
      expect(askedSuites(['flutter', 'test', '--concurrency=20']), 20);
      expect(askedSuites(['flutter', 'test', '--concurrency', '3']), 3);
      expect(askedSuites(['bash', 'x.sh', '-j', '9']), isNull);
    });

    test('a flutter test says how many test files it names — none for the '
        'whole suite or a folder', () {
      bool isFolder(String word) => word == 'test/tool';
      expect(
        filesAsked(['flutter', 'test', 'a_test.dart', 'b_test.dart']),
        2,
      );
      expect(
        filesAsked(
          ['timeout', '300', 'flutter', 'test', '-r', 'expanded', 'a_test.dart'],
          isFolder: isFolder,
        ),
        1,
      );
      expect(filesAsked(['flutter', 'test'], isFolder: isFolder), isNull);
      expect(
        filesAsked(
          ['flutter', 'test', 'test/tool', 'a_test.dart'],
          isFolder: isFolder,
        ),
        isNull,
      );
      expect(filesAsked(['dart', 'run', 'x.dart']), isNull);
      // A batch of affected_tests: its files, or the whole suite.
      expect(filesNamed(['--exclude-tags', 'gc'], isFolder: isFolder), isNull);
      expect(filesNamed(const []), isNull);
    });

    test('a flutter test says the work of the files it names, by this '
        "machine's times, in either slash", () {
      final known = {'test/a_test.dart': 3000, 'test/b_test.dart': 7000};
      expect(
        workAsked(
          ['flutter', 'test', 'test/a_test.dart', r'test\b_test.dart'],
          known,
        ),
        10,
      );
      expect(
        workAsked(
          ['timeout', '300', 'flutter', 'test', 'test/c_test.dart'],
          known,
        ),
        kUntimedFileMs ~/ 1000,
      );
      expect(workAsked(['flutter', 'test'], known), isNull);
      expect(workAsked(['dart', 'run', 'x.dart'], known), isNull);
    });

    test('its turn runs it at the suites the line gave, whatever it said', () {
      expect(placed(['flutter', 'test', 'a_test.dart'], 10), [
        'flutter', 'test', '--concurrency=10', 'a_test.dart', //
      ]);
      expect(placed(['flutter', 'test', '-j', '9', '--no-pub'], 5), [
        'flutter', 'test', '--concurrency=5', '--no-pub', //
      ]);
      expect(placed(['flutter', 'test', '-j12', '--concurrency=3'], 3), [
        'flutter', 'test', '--concurrency=3', //
      ]);
    });

    test('🚨a time limit stands INSIDE the turn, and its flutter test is '
        'still placed', () {
      // A limit put around test_queue counted the wait in line, and a mutant
      // that only waited read as killed (브러시/렌더링, 10-19).
      final command = [
        'timeout', '300', 'flutter', 'test', '-j', '9', 'a_test.dart', //
      ];
      expect(askedSuites(command), 9);
      expect(placed(command, 5), [
        'timeout', '300', 'flutter', 'test', '--concurrency=5', //
        'a_test.dart',
      ]);
    });

    test('any other command runs as it was given', () {
      expect(placed(['flutter', 'analyze'], 5), ['flutter', 'analyze']);
      expect(placed(['bash', 'x.sh', '-j', '9'], 5), [
        'bash', 'x.sh', '-j', '9', //
      ]);
    });
  });

  group('who is still in line', () {
    late Directory line;
    setUp(() => line = Directory.systemTemp.createTempSync('queue_fx'));
    tearDown(() => deleteTempQuietly(line));

    File ticket(String name, {DateTime? made, Object? told}) {
      final file = File('${line.path}/$name')..writeAsStringSync('1\n');
      File('${file.path}.json').writeAsStringSync(jsonEncode(told ?? {}));
      file.setLastModifiedSync(made ?? DateTime(2020));
      return file;
    }

    test('a settled ticket whose run ended is swept, with what it told', () {
      final gone = ticket('a.ticket');
      ticket('b.ticket');
      final held = heldTickets(
        line,
        mine: 'z.ticket',
        ended: (file) => nameOf(file) == nameOf(gone),
      );
      expect(held, ['b.ticket']);
      expect(gone.existsSync(), isFalse);
      expect(File('${gone.path}.json').existsSync(), isFalse);
    });

    test('⛔a ticket made a moment ago is not asked — it may not be locked '
        'yet', () {
      ticket('a.ticket', made: DateTime.now());
      final held = heldTickets(line, mine: 'z.ticket', ended: (_) => true);
      expect(held, ['a.ticket']);
    });

    test("this run's own ticket is held whatever the probe would say", () {
      ticket('mine.ticket');
      expect(
        heldTickets(line, mine: 'mine.ticket', ended: (_) => true),
        ['mine.ticket'],
      );
    });

    test('a ticket nobody holds has ended', () {
      expect(runHasEnded(ticket('a.ticket')), isTrue);
    });

    test('a ticket says its suites while running, its files, its work and '
        'since when; waiting or unreadable holds none', () {
      ticket('a.ticket', told: {
        'state': 'running',
        'suites': 5,
        'files': 1,
        'work': 300,
        'since': t0.toIso8601String(),
      });
      ticket('b.ticket', told: {'state': 'waiting', 'files': 2});
      ticket('c.ticket');
      File('${line.path}/d.ticket.json').writeAsStringSync('not json');
      expect(standingOf(line, 'a.ticket'), (
        name: 'a.ticket',
        suites: 5,
        files: 1,
        work: 300,
        since: t0,
      ));
      expect(standingOf(line, 'b.ticket'), (
        name: 'b.ticket',
        suites: null,
        files: 2,
        work: null,
        since: null,
      ));
      expect(standingOf(line, 'c.ticket').suites, isNull);
      expect(standingOf(line, 'd.ticket'), (
        name: 'd.ticket',
        suites: null,
        files: null,
        work: null,
        since: null,
      ));
    });

    test('--list shows the running runs, then the waiting ones in turn', () {
      ticket('a.ticket', told: {
        'state': 'waiting',
        'what': 'long',
        'work': 3600,
        'since': ago(60).toIso8601String(),
      });
      ticket('b.ticket', told: {
        'state': 'running',
        'suites': 5,
        'what': 'running',
        'work': 3000,
        'since': t0.toIso8601String(),
      });
      ticket('c.ticket', told: {
        'state': 'waiting',
        'what': 'short',
        'files': 2,
        'work': 120,
        'since': ago(60).toIso8601String(),
      });
      final rows = describeLine(line, now: t0);
      expect(rows, hasLength(3));
      expect(rows[0], startsWith('1. running 5 suites · ~50 machine-min'));
      expect(rows[1], startsWith('2. waiting · 2 files · ~2 machine-min'));
      expect(rows[1], contains(' · short · '));
      expect(rows[2], contains(' · long · '));
    });
  });

  group('a turn', () {
    late Directory line;
    setUp(() => line = Directory.systemTemp.createTempSync('queue_fx'));
    tearDown(() => deleteTempQuietly(line));

    List<String> tickets() => [
      for (final entity in line.listSync())
        if (entity.path.endsWith('.ticket')) entity.uri.pathSegments.last,
    ];

    /// A settled ticket another run took at [microseconds], telling [told].
    File standing(int microseconds, Map<String, Object> told) {
      final file = File('${line.path}/${ticketName(microseconds, 1)}')
        ..writeAsStringSync('1\n')
        ..setLastModifiedSync(DateTime(2020));
      File('${file.path}.json').writeAsStringSync(jsonEncode(told));
      return file;
    }

    File runningBefore(int microseconds, int suites) =>
        standing(microseconds, {'state': 'running', 'suites': suites});

    /// A ticket asked for after this run's own, telling [told].
    File askedAfter(Map<String, Object> told) => standing(
      DateTime.now().microsecondsSinceEpoch + 1000000000,
      told,
    );

    test('alone in an empty line it takes all ten, says what it took, and '
        'gives its ticket back', () async {
      final said = <String>[];
      final ran = await inTurn(
        'a run',
        (suites) async => (
          suites,
          tickets().length,
          standingOf(line, tickets().single).suites,
        ),
        line: line,
        room: () async => true,
        say: said.add,
      );
      expect(ran, (10, 1, 10));
      expect(tickets(), isEmpty);
      expect(said, isEmpty);
    });

    test('behind two runs holding the ten it starts only once one of them '
        'is given back — at five, beside the one still running', () async {
      final first = runningBefore(1, 5);
      runningBefore(2, 5);
      final events = <String>[];
      var asked = 0;
      await inTurn(
        'a run',
        (suites) async => events.add('ran at $suites'),
        line: line,
        room: () async => true,
        say: (_) => events.add('waits'),
        lookAgain: Duration.zero,
        ended: (file) {
          // The first run is given back on its third look.
          if (nameOf(file) != nameOf(first)) return false;
          asked++;
          final gone = asked == 3;
          events.add(gone ? 'given back' : 'held');
          return gone;
        },
      );
      expect(events, [
        'held', 'waits', 'held', 'given back', //
        // Asked once more under the line's lock before it starts.
        'ran at 5',
      ]);
      expect(first.existsSync(), isFalse);
    });

    test('🚨the line moved while the machine was measured: it reads the line '
        'again under the lock before it starts', () async {
      final events = <String>[];
      File? took;
      var looks = 0;
      await inTurn(
        'a run',
        (suites) async => events.add('ran at $suites'),
        line: line,
        room: () async {
          events.add('room measured');
          // Another run took all ten while this one measured.
          took ??= runningBefore(1, 10);
          return true;
        },
        say: (_) => events.add('waits'),
        lookAgain: Duration.zero,
        ended: (file) {
          if (nameOf(file) != nameOf(took!)) return false;
          looks++;
          final gone = looks == 3;
          if (gone) events.add('given back');
          return gone;
        },
      );
      expect(events, [
        'room measured', 'waits', 'given back', //
        'room measured', 'ran at 10',
      ]);
    });

    test('at its turn with no room it asks again, and runs once there is '
        'room', () async {
      final events = <String>[];
      var asks = 0;
      await inTurn(
        'a run',
        (suites) async => events.add('ran at $suites'),
        line: line,
        room: () async {
          asks++;
          events.add('room? ${asks == 3}');
          return asks == 3;
        },
        say: (_) => events.add('said'),
        askAgain: Duration.zero,
      );
      expect(events, [
        'room? false', 'said', 'room? false', 'room? true', 'ran at 10', //
      ]);
    });

    test('a one-file flutter test alone takes one suite', () async {
      final ran = await inTurn(
        'a run',
        (suites) async => suites,
        files: 1,
        line: line,
        room: () async => true,
      );
      expect(ran, 1);
    });

    test('a run of many batches keeps its place, says what each holds, and '
        'is decided afresh at every batch', () async {
      late File behind;
      Standing? whileWaiting;
      final seen = await standInLine(
        'a run',
        (turn) async {
          final mine = tickets().single;
          final first = await turn.take(files: 40, work: 2400);
          final whileRunning = standingOf(line, mine);
          turn.putDown();
          final between = standingOf(line, mine);
          // Another long run asks while the first batch runs.
          behind = askedAfter({'state': 'waiting'});
          final second = await turn.take(files: 40, work: 2400);
          return (
            first,
            whileRunning,
            between.suites,
            second,
            (tickets()..sort()).first == mine,
          );
        },
        line: line,
        room: () async {
          // What the rest of the line reads of a run deciding its batch.
          whileWaiting ??= standingOf(line, (tickets()..sort()).first);
          return true;
        },
        ended: (_) => false,
      );
      expect(whileWaiting!.suites, isNull);
      expect(whileWaiting!.files, 40);
      expect(whileWaiting!.work, 2400);
      expect(whileWaiting!.since, isNotNull);
      expect(seen.$1, 10);
      expect(seen.$2.suites, 10);
      expect(seen.$2.files, 40);
      expect(seen.$2.work, 2400);
      expect(
        seen.$2.since!.isBefore(whileWaiting!.since!),
        isFalse,
        reason: 'running, it says since when it runs',
      );
      expect(seen.$3, isNull);
      expect(seen.$4, 5);
      expect(seen.$5, isTrue);
      expect(tickets(), [nameOf(behind)]);
    });

    test('a long run at its next batch gives way to a short run that has '
        'waited longer, waits it out, then takes the machine again', () async {
      final events = <String>[];
      late File short;
      var looks = 0;
      await standInLine(
        'a run',
        (turn) async {
          events.add('batch at ${await turn.take()}');
          turn.putDown();
          short = askedAfter({
            'state': 'waiting',
            'files': 1,
            'work': 30,
            'since': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
          });
          events.add('batch at ${await turn.take()}');
          turn.putDown();
        },
        line: line,
        room: () async => true,
        say: (_) => events.add('waits'),
        lookAgain: Duration.zero,
        ended: (file) {
          if (nameOf(file) != nameOf(short)) return false;
          looks++;
          if (looks == 2) {
            File('${short.path}.json').writeAsStringSync(
              jsonEncode({
                'state': 'running',
                'suites': 1,
                'files': 1,
                'work': 30,
                'since': DateTime.now().toIso8601String(),
              }),
            );
            events.add('short runs at 1');
          }
          final gone = looks == 3;
          if (gone) events.add('short given back');
          return gone;
        },
      );
      expect(events, [
        'batch at 10', //
        // The short run is first in line, so the long run waits second…
        'waits', 'short runs at 1',
        // …then first, waiting it out, for a small run does not halve it…
        'waits', 'short given back',
        // …and then holds all ten again.
        'batch at 10',
      ]);
    });

    test('a run that asked for fewer is handed fewer', () async {
      final ran = await inTurn(
        'a run',
        (suites) async => suites,
        asked: 3,
        line: line,
        room: () async => true,
      );
      expect(ran, 3);
    });

    test('a run that throws still gives its ticket back', () async {
      await expectLater(
        inTurn<void>(
          'a run',
          (_) async => throw StateError('red'),
          line: line,
          room: () async => true,
        ),
        throwsStateError,
      );
      expect(tickets(), isEmpty);
    });
  });
}
