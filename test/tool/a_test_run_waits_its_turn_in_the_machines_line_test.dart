@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_queue.dart';
import '../helpers/temp_dir.dart';

/// A file by its name alone: Windows lists a folder with `\`, and the
/// paths these tests build use `/`.
String nameOf(File file) => file.uri.pathSegments.last;

/// 🗣️유저 2026-10-18 (tests-crowd-the-machine-Q1 「b」 — 「②기계 하나의 테스트
/// 대기열」) · 10-19 (「일일이 감시로 손으로 확인하는거말고 ci로해서 자원
/// 안쓰게」): the machine's test runs stand in one line of fixed places, each
/// place at fixed suites, and a run that waits launches nothing.
///
/// ⚠️WHAT THIS FILE CANNOT REACH: a ticket held by a DIFFERENT live process.
/// That needs a second process, which this corpus forbids
/// (`tests_do_not_race_the_code_test`), and POSIX locks belong to the
/// process, so one taken here is re-takeable here. Which tickets are held
/// is therefore handed in ([inTurn]'s `ended`), and the probe itself is
/// pinned only for a ticket nobody holds — as
/// `a_run_that_ended_leaves_its_room_test` pins the same law for the app's
/// rooms.
void main() {
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

    test('the first two held tickets have their turn, the third waits', () {
      final held = ['c.ticket', 'a.ticket', 'b.ticket'];
      expect(isMyTurn('a.ticket', held), isTrue);
      expect(isMyTurn('b.ticket', held), isTrue);
      expect(isMyTurn('c.ticket', held), isFalse);
      expect(isMyTurn('gone.ticket', held), isFalse);
      expect(kQueuePlaces, 2);
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

  group('a place', () {
    test('holds six suites, or fewer when the run asks for fewer', () {
      expect(kSuitesAPlace, 6);
      expect(suitesFor(null), 6);
      expect(suitesFor(4), 4);
      expect(suitesFor(6), 6);
      expect(suitesFor(12), 6);
    });

    test('a flutter test is run at the suites its place holds', () {
      expect(placed(['flutter', 'test', 'a_test.dart']), [
        'flutter', 'test', '--concurrency=6', 'a_test.dart', //
      ]);
      expect(placed(['flutter', 'test', '-j', '2', 'a_test.dart']), [
        'flutter', 'test', '--concurrency=2', 'a_test.dart', //
      ]);
      expect(placed(['flutter', 'test', '-j12', '--no-pub']), [
        'flutter', 'test', '--concurrency=6', '--no-pub', //
      ]);
      expect(placed(['flutter', 'test', '--concurrency=20']), [
        'flutter', 'test', '--concurrency=6', //
      ]);
      expect(placed(['flutter', 'test', '--concurrency', '3']), [
        'flutter', 'test', '--concurrency=3', //
      ]);
    });

    test('any other command runs as it was given', () {
      expect(placed(['flutter', 'analyze']), ['flutter', 'analyze']);
      expect(placed(['bash', 'x.sh', '-j', '9']), ['bash', 'x.sh', '-j', '9']);
    });
  });

  group('who is still in line', () {
    late Directory line;
    setUp(() => line = Directory.systemTemp.createTempSync('queue_fx'));
    tearDown(() => deleteTempQuietly(line));

    File ticket(String name, {DateTime? made}) {
      final file = File('${line.path}/$name')..writeAsStringSync('1\n');
      File('${file.path}.json').writeAsStringSync('{}');
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
  });

  group('a turn', () {
    late Directory line;
    setUp(() => line = Directory.systemTemp.createTempSync('queue_fx'));
    tearDown(() => deleteTempQuietly(line));

    List<String> tickets() => [
      for (final entity in line.listSync())
        if (entity.path.endsWith('.ticket')) entity.uri.pathSegments.last,
    ];

    File heldBefore(int microseconds) {
      final file = File('${line.path}/${ticketName(microseconds, 1)}')
        ..writeAsStringSync('1\n')
        ..setLastModifiedSync(DateTime(2020));
      return file;
    }

    test('an empty line runs at once and gives its ticket back', () async {
      final said = <String>[];
      final ran = await inTurn(
        'a run',
        () async => tickets().length,
        line: line,
        room: () async => true,
        say: said.add,
      );
      expect(ran, 1, reason: 'its own ticket stood while it ran');
      expect(tickets(), isEmpty);
      expect(said, isEmpty);
    });

    test('behind two held places it runs only once one of them is given '
        'back', () async {
      final first = heldBefore(1);
      heldBefore(2);
      final events = <String>[];
      var asked = 0;
      await inTurn(
        'a run',
        () async => events.add('ran'),
        line: line,
        room: () async => true,
        say: (_) => events.add('waits'),
        lookAgain: Duration.zero,
        ended: (file) {
          // The first place is given back on the third look.
          if (nameOf(file) != nameOf(first)) return false;
          asked++;
          final gone = asked == 3;
          events.add(gone ? 'given back' : 'held');
          return gone;
        },
      );
      expect(events, ['held', 'waits', 'held', 'given back', 'ran']);
      expect(first.existsSync(), isFalse);
    });

    test('at the head with no room it asks again, and runs once there is '
        'room', () async {
      final events = <String>[];
      var asks = 0;
      await inTurn(
        'a run',
        () async => events.add('ran'),
        line: line,
        room: () async {
          asks++;
          events.add('room? ${asks == 3}');
          return asks == 3;
        },
        say: (_) => events.add('said'),
        askAgain: Duration.zero,
      );
      expect(events, ['room? false', 'said', 'room? false', 'room? true', 'ran']);
    });

    test('a run that throws still gives its ticket back', () async {
      await expectLater(
        inTurn<void>(
          'a run',
          () async => throw StateError('red'),
          line: line,
          room: () async => true,
        ),
        throwsStateError,
      );
      expect(tickets(), isEmpty);
    });
  });
}
