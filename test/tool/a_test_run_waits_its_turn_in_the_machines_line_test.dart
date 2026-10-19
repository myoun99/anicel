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
/// 5개제한이잖아」): the machine's test runs stand in one line, hold ten suites
/// between them — all ten for a run alone, five each beside another — and a
/// run that waits launches nothing.
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
  Standing waiting(String name) => (name: name, suites: null);
  Standing runningAt(String name, int suites) => (name: name, suites: suites);

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

    test('⛔a run that started alone with all ten is waited out, not joined',
        () {
      expect(suitesToRun('b', [runningAt('a', 10), waiting('b')]), isNull);
      // …though one that asked for fewer leaves the rest.
      expect(suitesToRun('b', [runningAt('a', 3), waiting('b')]), 5);
    });

    test('⛔nobody starts ahead of a run still waiting, and a third waits '
        'while two hold the ten', () {
      expect(suitesToRun('b', [waiting('a'), waiting('b')]), isNull);
      expect(
        suitesToRun('c', [runningAt('a', 5), runningAt('b', 5), waiting('c')]),
        isNull,
      );
      expect(suitesToRun('gone', [waiting('a')]), isNull);
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

    test('a running ticket says its suites; waiting or unreadable says none',
        () {
      ticket('a.ticket', told: {'state': 'running', 'suites': 5});
      ticket('b.ticket', told: {'state': 'waiting'});
      ticket('c.ticket');
      File('${line.path}/d.ticket.json').writeAsStringSync('not json');
      expect(suitesOf(line, 'a.ticket'), 5);
      expect(suitesOf(line, 'b.ticket'), isNull);
      expect(suitesOf(line, 'c.ticket'), isNull);
      expect(suitesOf(line, 'd.ticket'), isNull);
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

    File runningBefore(int microseconds, int suites) {
      final file = File('${line.path}/${ticketName(microseconds, 1)}')
        ..writeAsStringSync('1\n')
        ..setLastModifiedSync(DateTime(2020));
      File('${file.path}.json').writeAsStringSync(
        jsonEncode({'state': 'running', 'suites': suites}),
      );
      return file;
    }

    test('alone in an empty line it takes all ten, says what it took, and '
        'gives its ticket back', () async {
      final said = <String>[];
      final ran = await inTurn(
        'a run',
        (suites) async => (suites, tickets().length, suitesOf(line, tickets().single)),
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
