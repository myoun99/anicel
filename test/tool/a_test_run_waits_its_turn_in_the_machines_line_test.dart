@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/flutter_room.dart' show FlutterRun;
import '../../tool/test_queue.dart';
import '../../tool/test_seconds.dart' show kUntimedFileMs;
import '../helpers/project_scratch_folder.dart';
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
/// first, and a run that waits launches nothing. And since 10-20 (「계속 10줄
/// 중 아까 낮처럼 2개쓴다거나 지금처럼 6개만쓴다거나 이런거 안일어나게」) none of
/// the ten stands free while a run waits: what the runs ahead leave goes to
/// the next, short of its share if that is all there is.
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
  // A run is named here as its ticket is: when it was asked, then who it is
  // — the line reads since when it stands off the name ([askedAt]).
  String askedAs(String who, int waited) =>
      '${ago(waited).microsecondsSinceEpoch.toString().padLeft(17, '0')}-$who';
  String whoOf(String name) => name.substring(name.indexOf('-') + 1);
  /// [old]: its tool is from before the line handed out what is left.
  Standing waiting(
    String who, {
    int? files,
    int? work,
    int waited = 0,
    bool old = false,
  }) => (
    name: askedAs(who, waited),
    suites: null,
    files: files,
    work: work,
    since: null,
    takesWhatIsLeft: !old,
  );
  Standing runningAt(String who, int suites, {int? files, int? work}) => (
    name: askedAs(who, 0),
    suites: suites,
    files: files,
    work: work,
    since: null,
    takesWhatIsLeft: true,
  );
  int? decide(
    String mine,
    List<Standing> line, {
    int? asked,
    int machine = kMachineSuites,
  }) => suitesToRun(
    [
      for (final s in line)
        if (whoOf(s.name) == mine) s.name,
    ].firstOrNull ?? mine,
    line,
    asked: asked,
    now: t0,
    machine: machine,
  );
  List<String> turnOrder(List<Standing> line) => [
    for (final s in waitingInTurn(line, t0)) whoOf(s.name),
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
      expect(decide('a', [waiting('a'), waiting('b')]), 5);
    });

    test('🗣️a machine whose line names its own number holds that many — '
        'all of them alone, half each beside another', () {
      // 유저 10-21: 「10줄이 진짜 괜찮나? … 12줄이나 15줄이나」.
      expect(decide('a', [waiting('a')], machine: 14), 14);
      expect(decide('a', [waiting('a'), waiting('b')], machine: 14), 7);
      expect(decide('b', [runningAt('a', 7), waiting('b')], machine: 14), 7);
      expect(decide('b', [runningAt('a', 10), waiting('b')], machine: 14), 4);
      expect(decide('b', [runningAt('a', 10), waiting('b')]), isNull);
    });

    test('the number is what the line folder\'s file says — ten when it '
        'says none', () {
      final line = Directory.systemTemp.createTempSync('queue_n');
      addTearDown(() => deleteAfterSessionEnds(line));
      expect(machineSuitesOf(line), kMachineSuites);
      final said = File('${line.path}/$kSuitesFile');
      said.writeAsStringSync('14\n');
      expect(machineSuitesOf(line), 14);
      for (final none in ['0', '-3', 'twelve', '']) {
        said.writeAsStringSync(none);
        expect(machineSuitesOf(line), kMachineSuites, reason: none);
      }
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
        'longer takes what it leaves', () {
      final line = [
        waiting('long', work: 3600, waited: 60),
        waiting('short', work: 300, waited: 60),
      ];
      expect(turnOrder(line), ['short', 'long']);
      expect(decide('short', line), 5);
      expect(decide('long', line), 5);
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

    test('⚠️a run of a tool from before stands from when it says it began '
        'to wait — as it reads its own turn', () {
      // Two runs that each read the other as first held six of eighteen
      // suites idle the evening the run kept its place (Q15).
      final old = (
        name: askedAs('old', 1000),
        suites: null,
        files: null,
        work: null,
        since: ago(10),
        takesWhatIsLeft: true,
      );
      expect(turnOrder([old, waiting('new', waited: 100)]), ['new', 'old']);
      expect(turnOrder([waiting('new', waited: 5), old]), ['old', 'new']);
    });

    test('beside the first in line a run starts when both fit now — and '
        'takes what is left after the first', () {
      expect(decide('b', [waiting('a'), waiting('b')]), 5);
      final line = [runningAt('r', 2), waiting('a'), waiting('b')];
      expect(decide('a', line), 5);
      expect(decide('b', line), 3);
    });

    test('🚨the first in line takes what stands free, short of its share — '
        'none is kept idle for it', () {
      // 유저 10-20: 「계속 10줄 중 아까 낮처럼 2개쓴다거나 지금처럼 6개만쓴다거나
      // 이런거 안일어나게 하고싶어」. ↩️It waited for its five while the two
      // stood free, and a run behind it took them only if the line could
      // tell it would end in time.
      final line = [
        runningAt('r', 5, work: 3000),
        runningAt('q', 3),
        waiting('first', waited: 1000),
        waiting('s', files: 2, work: 60),
      ];
      expect(turnOrder(line).first, 'first');
      expect(decide('first', line), 2);
      expect(decide('s', line), isNull);
    });

    test('what the runs ahead take goes down the line in turn, until the ten '
        'are held', () {
      final line = [
        runningAt('r', 2),
        waiting('short', files: 3, work: 60, waited: 60),
        waiting('a', waited: 10),
        waiting('b'),
      ];
      expect(turnOrder(line), ['short', 'a', 'b']);
      expect(decide('short', line), 3);
      expect(decide('a', line), 5);
      expect(decide('b', line), isNull);
    });

    test('⚠️a run of a tool from before takes all of its share or waits — '
        'so what it would not take now is not kept for it', () {
      final line = [
        runningAt('r', 7),
        waiting('old', waited: 1000, old: true),
        waiting('s', files: 2, work: 60),
      ];
      expect(turnOrder(line).first, 'old');
      expect(decide('s', line), 2);
      // When its share does stand free, it takes it first.
      line[0] = runningAt('r', 5);
      expect(decide('s', line), isNull);
    });

    test('⛔small runs do not halve a long run — it takes all they leave', () {
      expect(
        decide('a', [waiting('a'), runningAt('s', 1, files: 1, work: 600)]),
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
        'how it takes; waiting or unreadable holds none', () {
      ticket('a.ticket', told: {
        'state': 'running',
        'suites': 5,
        'files': 1,
        'work': 300,
        'takesWhatIsLeft': true,
      });
      // A tool from before 10-21 also says since when it began to wait.
      ticket('b.ticket', told: {
        'state': 'waiting',
        'files': 2,
        'since': t0.toIso8601String(),
      });
      ticket('c.ticket');
      File('${line.path}/d.ticket.json').writeAsStringSync('not json');
      expect(standingOf(line, 'a.ticket'), (
        name: 'a.ticket',
        suites: 5,
        files: 1,
        work: 300,
        since: null,
        takesWhatIsLeft: true,
      ));
      // A tool from before says nothing of how it takes: all or nothing.
      expect(standingOf(line, 'b.ticket'), (
        name: 'b.ticket',
        suites: null,
        files: 2,
        work: null,
        since: t0,
        takesWhatIsLeft: false,
      ));
      expect(standingOf(line, 'c.ticket').suites, isNull);
      expect(standingOf(line, 'd.ticket'), (
        name: 'd.ticket',
        suites: null,
        files: null,
        work: null,
        since: null,
        takesWhatIsLeft: false,
      ));
    });

    test('--list shows the running runs, then the waiting ones in turn', () {
      final aMinuteAgo = ago(60).microsecondsSinceEpoch;
      ticket(ticketName(aMinuteAgo, 1), told: {
        'state': 'waiting',
        'what': 'long',
        'work': 3600,
      });
      ticket(ticketName(t0.microsecondsSinceEpoch, 2), told: {
        'state': 'running',
        'suites': 5,
        'what': 'running',
        'work': 3000,
      });
      ticket(ticketName(aMinuteAgo, 3), told: {
        'state': 'waiting',
        'what': 'short',
        'files': 2,
        'work': 120,
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

    test('🗣️with the line\'s file at fourteen, beside two runs holding ten '
        'it starts at once on the four left', () async {
      File('${line.path}/$kSuitesFile').writeAsStringSync('14');
      final first = runningBefore(1, 5);
      runningBefore(2, 5);
      final events = <String>[];
      var looks = 0;
      await inTurn(
        'a run',
        (suites) async => events.add('ran at $suites'),
        line: line,
        room: () async => true,
        say: (_) => events.add('waits'),
        lookAgain: Duration.zero,
        ended: (file) => nameOf(file) == nameOf(first) && ++looks > 2,
      );
      expect(events, ['ran at 4']);
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

    test('a run of many batches keeps its ticket, says what each holds, and '
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
      expect(
        whileWaiting!.takesWhatIsLeft,
        isTrue,
        reason: 'the rest of the line keeps nothing for a run of this tool '
            'that it would not take',
      );
      expect(seen.$1, 10);
      expect(seen.$2.suites, 10);
      expect(seen.$2.files, 40);
      expect(seen.$2.work, 2400);
      expect(seen.$3, isNull);
      expect(seen.$4, 5);
      expect(seen.$5, isTrue);
      expect(tickets(), [nameOf(behind)]);
    });

    test('🚨a long run at its next batch takes what a short run that waited '
        'longer leaves it — it waits nothing out', () async {
      // ↩️Until 유저 10-20 (「…6개만쓴다거나 이런거 안일어나게」) it waited
      // second, then first, until the short run was given back, and held
      // all ten again — nine standing free meanwhile.
      final events = <String>[];
      late File short;
      var looks = 0;
      await standInLine(
        'a run',
        (turn) async {
          events.add('batch at ${await turn.take()}');
          turn.putDown();
          short = standing(
            DateTime.now()
                .subtract(const Duration(minutes: 1))
                .microsecondsSinceEpoch,
            {
              'state': 'waiting',
              'files': 1,
              'work': 30,
              'takesWhatIsLeft': true,
            },
          );
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
              }),
            );
            events.add('short runs at 1');
          }
          return false;
        },
      );
      expect(events, [
        'batch at 10', //
        // The short run is first in line and takes its one; the long run
        // takes the nine beside it, never waiting.
        'short runs at 1', 'batch at 9',
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

  group("the machine's room", () {
    test('🚨the line asks for the headroom alone — its runs take none of the '
        'four places', () async {
      // 유저 tests-crowd-the-machine-Q9 「line」(10-20): at 18:00 the line used
      // six suites of ten while nineteen runs waited, every place held.
      final asked = <bool>[];
      final room = await machineHasRoom(
        measure: ({required headroomAlone}) async {
          asked.add(headroomAlone);
          return (
            taken: 9,
            freeGb: 4,
            room: headroomAlone,
            runs: const <FlutterRun>[],
            bashRead: true,
          );
        },
      );
      expect(asked, [true]);
      expect(room, isTrue);
    });

    test('⛔a machine that could not be measured has no room', () async {
      expect(await machineHasRoom(measure: ({required headroomAlone}) async {
        return null;
      }), isFalse);
    });
  });

  group("the line's record of itself", () {
    late Directory line;
    setUp(() => line = Directory.systemTemp.createTempSync('queue_fx'));
    tearDown(() => deleteTempQuietly(line));

    List<String> rows() => [
      for (final row in File('${line.path}/$kUsageFile').readAsLinesSync())
        row.split('\t').skip(1).join('\t'),
    ];

    test('a turn writes a row as it waits, takes its suites, puts them down '
        'and leaves: the suites held, and how many wait', () async {
      await standInLine(
        'a run',
        (turn) async {
          await turn.take();
          turn.putDown();
        },
        line: line,
        room: () async => true,
      );
      expect(rows(), ['0\t1', '10\t0', '0\t1', '0\t0']);
    });

    test('a row counts every ticket there — running, waiting, or one that '
        'said nothing', () {
      File('${line.path}/a.ticket').writeAsStringSync('1\n');
      File('${line.path}/a.ticket.json').writeAsStringSync(
        jsonEncode({'state': 'running', 'suites': 5}),
      );
      File('${line.path}/b.ticket').writeAsStringSync('1\n');
      File('${line.path}/c.ticket').writeAsStringSync('1\n');
      File('${line.path}/c.ticket.json').writeAsStringSync(
        jsonEncode({'state': 'running', 'suites': 3}),
      );
      noteUsage(line);
      expect(rows(), ['8\t1']);
    });

    test('⛔a record past its size keeps its later half', () {
      final file = File('${line.path}/$kUsageFile')
        ..writeAsStringSync(
          '${List.filled(kUsageKeeps ~/ 20, '${t0.toIso8601String()}\t1\t1').join('\n')}\n',
        );
      noteUsage(line);
      final kept = file.readAsLinesSync();
      expect(file.lengthSync(), lessThan(kUsageKeeps));
      expect(kept.last, endsWith('\t0\t0'));
    });

    test('how long runs waited, and the suites held meanwhile — a row stands '
        'until the next, the last until the end', () {
      String row(int seconds, int held, int waiting) =>
          '${t0.add(Duration(seconds: seconds)).toIso8601String()}'
          '\t$held\t$waiting';
      final record = [
        row(120, 3, 0),
        'not a row',
        row(0, 5, 2),
        row(60, 10, 1),
      ];
      final whole = usageOf(
        record,
        from: t0,
        to: t0.add(const Duration(seconds: 180)),
      );
      expect(whole.waited, const Duration(seconds: 120));
      expect(whole.held, 7.5);
      // From halfway through the first row, and a row before the window.
      final later = usageOf(
        record,
        from: t0.add(const Duration(seconds: 30)),
        to: t0.add(const Duration(seconds: 180)),
      );
      expect(later.waited, const Duration(seconds: 90));
      expect(later.held, closeTo((5 * 30 + 10 * 60) / 90, 1e-9));
      // While nobody waits, nothing is counted.
      expect(
        usageOf([row(0, 2, 0)], from: t0, to: t0.add(const Duration(hours: 1)))
            .waited,
        Duration.zero,
      );
    });
  });
}
