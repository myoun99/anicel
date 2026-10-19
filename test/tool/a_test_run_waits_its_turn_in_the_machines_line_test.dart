@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_queue.dart';
import '../helpers/temp_dir.dart';

/// A file by its name alone: Windows lists a folder with `\`, and the
/// paths these tests build use `/`.
String nameOf(File file) => file.uri.pathSegments.last;

/// 🗣️유저 2026-10-18 (tests-crowd-the-machine-Q1 「b」 — 「②기계 하나의 테스트
/// 대기열」) · 10-19 (「일일이 감시로 손으로 확인하는거말고 ci로해서 자원
/// 안쓰게」 · 「최대가 10만되게 할수있나. 지금상태면 단독진행일때
/// 5개제한이잖아」 · Q3 「짧은 실행은 틈에 끼운다」): the machine's test runs
/// stand in one line, hold ten suites between them — all ten for a run
/// alone, five each beside another, a short run its files in the gaps — and
/// a run that waits launches nothing.
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
  Standing waiting(String name, {int? files}) =>
      (name: name, suites: null, files: files);
  Standing runningAt(String name, int suites, {int? files}) =>
      (name: name, suites: suites, files: files);

  group('the line', () {
    test('a ticket asked for earlier sorts first', () {
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
    });

    test('ten suites between every run; half each when two share', () {
      expect(kMachineSuites, 10);
      expect(kSharedSuites, 5);
    });

    test('a run alone in the line takes the machine — or what it asked for',
        () {
      expect(suitesToRun('a', [waiting('a')]), 10);
      expect(suitesToRun('a', [waiting('a')], asked: 4), 4);
      expect(suitesToRun('a', [waiting('a')], asked: 20), 10);
    });

    test('with anyone else in line, ahead or behind, a run takes half', () {
      expect(suitesToRun('a', [waiting('a'), waiting('b')]), 5);
      expect(suitesToRun('b', [runningAt('a', 5), waiting('b')]), 5);
    });

    test('⛔a run holding all ten is waited out, not joined', () {
      expect(suitesToRun('b', [runningAt('a', 10), waiting('b')]), isNull);
      // …though one that asked for fewer leaves the rest.
      expect(suitesToRun('b', [runningAt('a', 3), waiting('b')]), 5);
    });

    test('⛔no long run starts ahead of a long run still waiting, and a third '
        'waits while two hold the ten', () {
      expect(suitesToRun('b', [waiting('a'), waiting('b')]), isNull);
      expect(
        suitesToRun('c', [runningAt('a', 5), runningAt('b', 5), waiting('c')]),
        isNull,
      );
      expect(suitesToRun('gone', [waiting('a')]), isNull);
    });

    test('a short run is charged the files it names', () {
      expect(kShortRun, 2);
      expect(suitesToRun('a', [waiting('a', files: 1)]), 1);
      expect(suitesToRun('a', [waiting('a', files: 2)], asked: 1), 1);
      // A long run's last batch of three takes three.
      expect(suitesToRun('a', [waiting('a', files: 3)]), 3);
    });

    test('a short run starts out of turn in the gap the running runs leave',
        () {
      final line = [
        runningAt('a', 5),
        waiting('b'),
        waiting('s', files: 1),
      ];
      expect(suitesToRun('s', line), 1);
      // …and the long run ahead of it keeps that room for it.
      expect(suitesToRun('b', line), isNull);
      // ⛔A short run waiting ahead holds no long run's turn.
      expect(
        suitesToRun('b', [waiting('s', files: 1), waiting('b')], asked: 9),
        9,
      );
    });

    test('⛔with no gap a short run waits', () {
      expect(
        suitesToRun('s', [
          runningAt('a', 5),
          runningAt('b', 5),
          waiting('s', files: 1),
        ]),
        isNull,
      );
    });

    test('a long run deciding its next batch keeps room for every short run '
        'still waiting', () {
      final line = [
        waiting('a'),
        runningAt('b', 5),
        waiting('s', files: 1),
      ];
      expect(suitesToRun('a', line), isNull);
      expect(suitesToRun('s', line), 1);
    });

    test('a short run keeps the gap for the short runs ahead of it, not '
        'behind', () {
      final line = [
        runningAt('a', 8, files: 9),
        waiting('s', files: 1),
        waiting('t', files: 2),
      ];
      expect(suitesToRun('s', line), 1);
      expect(suitesToRun('t', line), isNull);
    });

    test('⛔short runs do not halve a long run — it waits them out and takes '
        'the machine', () {
      expect(
        suitesToRun('a', [waiting('a'), runningAt('s', 1, files: 1)]),
        isNull,
      );
      expect(suitesToRun('a', [waiting('a'), waiting('s', files: 2)]), isNull);
      expect(
        suitesToRun('a', [waiting('a'), runningAt('s', 1, files: 1)], asked: 9),
        9,
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

    test('a ticket says its suites while running and its files; waiting or '
        'unreadable holds none', () {
      ticket('a.ticket', told: {'state': 'running', 'suites': 5, 'files': 1});
      ticket('b.ticket', told: {'state': 'waiting', 'files': 2});
      ticket('c.ticket');
      File('${line.path}/d.ticket.json').writeAsStringSync('not json');
      expect(standingOf(line, 'a.ticket'), (
        name: 'a.ticket',
        suites: 5,
        files: 1,
      ));
      expect(standingOf(line, 'b.ticket'), (
        name: 'b.ticket',
        suites: null,
        files: 2,
      ));
      expect(standingOf(line, 'c.ticket').suites, isNull);
      expect(standingOf(line, 'd.ticket'), (
        name: 'd.ticket',
        suites: null,
        files: null,
      ));
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
          final first = await turn.take(files: 40);
          final whileRunning = standingOf(line, mine);
          turn.putDown();
          final between = standingOf(line, mine);
          // Another long run asks while the first batch runs.
          behind = askedAfter({'state': 'waiting'});
          final second = await turn.take(files: 40);
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
      expect(seen.$1, 10);
      expect(seen.$2.suites, 10);
      expect(seen.$2.files, 40);
      expect(seen.$3, isNull);
      expect(seen.$4, 5);
      expect(seen.$5, isTrue);
      expect(tickets(), [nameOf(behind)]);
    });

    test('a long run gives the gap to a short run waiting at its next batch, '
        'then takes the machine again', () async {
      final events = <String>[];
      late File short;
      var looks = 0;
      await standInLine(
        'a run',
        (turn) async {
          events.add('batch at ${await turn.take()}');
          turn.putDown();
          short = askedAfter({'state': 'waiting', 'files': 1});
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
          if (looks == 1) {
            File('${short.path}.json').writeAsStringSync(
              jsonEncode({'state': 'running', 'suites': 1, 'files': 1}),
            );
            events.add('short runs at 1');
          }
          final gone = looks == 2;
          if (gone) events.add('short given back');
          return gone;
        },
      );
      expect(events, [
        'batch at 10', //
        // The short run's room is kept, so the long run waits it out…
        'short runs at 1', 'waits', 'short given back',
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
