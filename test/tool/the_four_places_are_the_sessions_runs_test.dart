import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/flutter_room.dart';

/// 🚨THE FOUR PLACES ARE THE SESSIONS' RUNS (card a-sent-lane-is-gated-once).
///
/// CLAUDE.md's 「Flutter 실행은 여유만큼」 lets every session together have
/// four Flutter runs going. Until 2026-10-08 each session counted them with
/// a script of its own, and every one of those counted 「dart.exe whose
/// command line names the Flutter tool」. The 관제 session measured it that
/// night: SIX were counted while the sessions had THREE runs going —
/// Android Studio's helper and its debug app held two of the four places,
/// and one device test held two by itself. A lane sent from the other
/// machine waited for a place that no session's run was in.
///
/// 유저 chose on the board that day: what is counted is what a session
/// launched (a-sent-lane-is-gated-once-Q2), and a land's gates are outside
/// the four (…-Q1).
///
/// ⚠️The chains below are the ones Windows listed that night, numbers and
/// all; where one is built by hand instead, its test says so.
void main() {
  WindowsProcess win(
    int pid,
    int parent,
    String name, {
    String? asked,
    int born = 0,
  }) => WindowsProcess(
    pid: pid,
    parent: parent,
    name: name,
    asked: asked,
    born: born,
  );
  BashProcess sh(int pid, int parent, int winPid) =>
      BashProcess(pid: pid, parent: parent, winPid: winPid);

  // Android Studio, with the app running from it: its helper and the debug
  // app, each as the tool's two processes.
  final androidStudio = [
    win(39320, 20364, 'explorer.exe'),
    win(53084, 39320, 'studio64.exe'),
    win(14296, 53084, 'cmd.exe'),
    win(50072, 14296, 'dart.exe', asked: 'daemon'),
    win(14680, 50072, 'dartvm.exe', asked: 'daemon'),
    win(51956, 53084, 'cmd.exe'),
    win(42992, 51956, 'dart.exe', asked: '--no-color run --machine'),
    win(47800, 42992, 'dartvm.exe', asked: '--no-color run --machine'),
  ];

  // A session, down to the shell its commands start in. The app's own
  // parent was gone.
  final aSession = [
    win(8780, 10844, 'claude.exe'),
    win(35616, 8780, 'claude.exe'),
    win(49188, 35616, 'bash.exe'),
    win(48932, 49188, 'bash.exe'),
  ];

  // One `flutter test` that session launched from Git Bash, under
  // `dart run tool/affected_tests.dart`. On Windows' side it ends at a
  // bash whose parent is gone…
  final aRunFromBash = [
    win(52580, 47168, 'bash.exe'),
    win(52528, 52580, 'cmd.exe'),
    win(11836, 52528, 'dart.exe'),
    win(51884, 11836, 'dartvm.exe'),
    win(51616, 51884, 'cmd.exe'),
    win(46048, 51616, 'dart.exe', asked: 'test --no-pub test/ui/menu'),
    win(44500, 46048, 'dartvm.exe', asked: 'test --no-pub test/ui/menu'),
    win(47704, 52336, 'bash.exe'),
  ];

  // …and bash's own table leads from that `cmd.exe` up to the session's
  // shell.
  final itsBashRows = [
    sh(647956, 1, 48932),
    sh(647957, 647956, 18008),
    sh(648007, 647957, 47704),
    sh(648136, 648007, 43776),
    sh(648237, 648136, 52528),
  ];

  List<FlutterRun> runsOf(
    List<WindowsProcess> windows, {
    List<BashProcess> bash = const [],
    int? landHolder,
  }) => Machine(
    windows: windows,
    bash: bash,
  ).flutterRuns(landHolder: landHolder);

  group('whose a run is', () {
    test('🚨Android Studio\'s helper and its debug app are the user\'s own — '
        'neither takes one of the four', () {
      final runs = runsOf(androidStudio);

      expect(runs.map((run) => run.pid), unorderedEquals([50072, 42992]));
      expect(runs.map((run) => run.of), everyElement(RunOf.user));
      expect(RunOf.user.takesAPlace, isFalse);
    });

    test('a run a session launched from Git Bash is that session\'s — found '
        'through bash\'s own table', () {
      final runs = runsOf([
        ...aSession,
        ...aRunFromBash,
      ], bash: itsBashRows);

      expect(runs.single.pid, 46048);
      expect(runs.single.of, RunOf.session);
      expect(RunOf.session.takesAPlace, isTrue);
    });

    test('🚨with no table to follow, that run is launched by nobody that '
        'can be named — and STILL takes a place', () {
      final runs = runsOf([...aSession, ...aRunFromBash]);

      expect(runs.single.of, RunOf.nobody);
      expect(RunOf.nobody.takesAPlace, isTrue);
    });

    // Built by hand: the app started from the desktop, and a run launched
    // from its PowerShell — Windows' parents alone reach both.
    test('a session\'s run is the session\'s even with the desktop above '
        'the session', () {
      final runs = runsOf([
        win(39320, 20364, 'explorer.exe'),
        win(100, 39320, 'claude.exe'),
        win(101, 100, 'claude.exe'),
        win(102, 101, 'powershell.exe'),
        win(103, 102, 'cmd.exe'),
        win(104, 103, 'dart.exe', asked: 'test test/ui'),
      ]);

      expect(runs.single.of, RunOf.session);
    });

    // Built by hand: whatever started Android Studio is gone, so nothing
    // above it is the desktop.
    test('Android Studio\'s are the user\'s by its own name', () {
      final runs = runsOf([
        win(53084, 9999, 'studio64.exe'),
        win(14296, 53084, 'cmd.exe'),
        win(50072, 14296, 'dart.exe', asked: 'daemon'),
      ]);

      expect(runs.single.of, RunOf.user);
    });

    // Built by hand, from the answer's own words — 「직접 돌리시는
    // 빌드(릴리즈 포함)」. Windows spells a name the way its file was
    // started; the capitals are not ours to rely on.
    test('a build the user runs from a terminal is the user\'s own', () {
      final runs = runsOf([
        win(39320, 20364, 'Explorer.EXE'),
        win(200, 39320, 'WindowsTerminal.exe'),
        win(201, 200, 'powershell.exe'),
        win(202, 201, 'cmd.exe'),
        win(203, 202, 'dart.exe', asked: 'build windows --release'),
      ]);

      expect(runs.single.of, RunOf.user);
    });

    // Built by hand on the measured shape: the same cut chain as a
    // session's run, under a Git Bash window the user opened.
    final fromTheUsersBash = [
      win(39320, 20364, 'explorer.exe'),
      win(300, 39320, 'mintty.exe'),
      win(301, 300, 'bash.exe'),
      win(310, 9999, 'bash.exe'),
      win(311, 310, 'cmd.exe'),
      win(312, 311, 'dart.exe', asked: 'build apk --release'),
    ];

    test('…and from a Git Bash window: bash\'s table leads to the window '
        'the user opened', () {
      final runs = runsOf(
        fromTheUsersBash,
        bash: [sh(800, 1, 301), sh(801, 800, 311)],
      );

      expect(runs.single.of, RunOf.user);
    });

    test('🚨a dead parent\'s number worn by a newer process names nobody', () {
      // The bash that launched the run was 39560's child. 39560 is gone,
      // and something the user started from the desktop has the number now.
      final runs = runsOf([
        win(39320, 20364, 'explorer.exe', born: 1),
        win(36368, 39560, 'bash.exe', born: 10),
        win(4232, 36368, 'cmd.exe', born: 20),
        win(20116, 4232, 'dart.exe', asked: 'test -j 1', born: 30),
        win(39560, 39320, 'notepad.exe', born: 99),
      ]);

      expect(runs.single.of, RunOf.nobody);
    });
  });

  group('one run is counted once', () {
    test('the tool\'s own second process — dartvm.exe under dart.exe — is '
        'no second run', () {
      expect(runsOf(androidStudio), hasLength(2));
      expect(
        androidStudio.where((process) => process.asked != null),
        hasLength(4),
        reason: 'premise: four processes carry the tool\'s name',
      );
    });

    // The 관제 session's measurement, 2026-10-08 01:59: a device test
    // builds the app through cmake and MSBuild, and that build asks the
    // Flutter tool again.
    test('🚨a build step a device test launches under itself is no second '
        'run', () {
      final runs = runsOf([
        ...aSession,
        win(500, 48932, 'cmd.exe'),
        win(501, 500, 'dart.exe', asked: 'test integration_test/a_test.dart'),
        win(502, 501, 'dartvm.exe', asked: 'test integration_test/a_test.dart'),
        win(503, 502, 'cmake.exe'),
        win(504, 503, 'MSBuild.exe'),
        win(505, 504, 'cmd.exe'),
        win(506, 505, 'cmake.exe'),
        win(507, 506, 'dart.exe', asked: 'assemble -dTargetPlatform'),
        win(508, 507, 'dartvm.exe', asked: 'assemble -dTargetPlatform'),
      ]);

      expect(runs.single.pid, 501);
    });

    test('a run under a tool that is not Flutter\'s IS a run', () {
      // `dart run tool/affected_tests.dart` (11836) names no Flutter tool.
      final runs = runsOf([...aSession, ...aRunFromBash], bash: itsBashRows);

      expect(runs.single.asked, 'test --no-pub test/ui/menu');
    });
  });

  group('a land\'s gates', () {
    // Built by hand on the measured shape: the lane script (bash's 5001)
    // under another shell of the session, a subshell under it, and
    // `flutter analyze` ending — on Windows' side — at a bash whose parent
    // is gone.
    final aGate = [
      ...aSession,
      win(48940, 49188, 'bash.exe'),
      win(902, 7777, 'bash.exe'),
      win(901, 902, 'cmd.exe'),
      win(900, 901, 'dart.exe', asked: 'analyze'),
      win(960, 8888, 'bash.exe'),
    ];
    final itsRows = [
      sh(5000, 1, 48940),
      sh(5001, 5000, 960),
      sh(5002, 5001, 950),
      sh(5003, 5002, 901),
    ];

    test('🚨what the landing lane\'s script launched takes no place', () {
      final runs = runsOf(aGate, bash: itsRows, landHolder: 5001);

      expect(runs.single.of, RunOf.land);
      expect(RunOf.land.takesAPlace, isFalse);
    });

    test('⛔and only that: with no land under way, or a number in the turn '
        'that is nobody\'s, the same run is the session\'s', () {
      expect(runsOf(aGate, bash: itsRows).single.of, RunOf.session);
      expect(
        runsOf(aGate, bash: itsRows, landHolder: 4242).single.of,
        RunOf.session,
      );
    });

    test('a run beside the land is counted as ever', () {
      final runs = runsOf(
        [...aGate, ...aRunFromBash],
        bash: [...itsRows, ...itsBashRows],
        landHolder: 5001,
      );

      expect(
        {for (final run in runs) run.pid: run.of},
        {900: RunOf.land, 46048: RunOf.session},
      );
    });
  });

  group('room', () {
    bool room(int taken, int freeGb, {bool aLand = false}) =>
        roomFor(taken: taken, freeGb: freeGb, aLand: aLand);

    test('one more run wants a place AND the headroom', () {
      expect(room(3, 4), isTrue);
      expect(room(4, 9), isFalse, reason: 'the four are taken');
      expect(room(3, 3), isFalse, reason: 'under 4GB');
    });

    test('🚨a land\'s gates want the headroom alone', () {
      expect(room(7, 4, aLand: true), isTrue);
      expect(room(0, 3, aLand: true), isFalse);
    });

    test('the two numbers are the ones CLAUDE.md states', () {
      final law = File('CLAUDE.md').readAsStringSync();

      expect(law, contains('커밋 여유 ${kHeadroomGb}GB'));
      expect(law, contains('최대 $kFlutterPlaces개'));
      expect(law, contains('dart tool/flutter_room.dart'));
    });
  });

  group('reading the machine', () {
    test('Windows\' answer: the free commit in whole GB, every process, and '
        'what the tool was asked only where it IS the tool', () {
      final answer = windowsAnswerFrom(
        [
          'free\t9437184',
          'proc\t39320\t20364\t100\t0\texplorer.exe\t',
          'proc\t50072\t14296\t200\t1\tdart.exe\tdaemon',
          'proc\t50073\t14296\t200\t1\tdart.exe\t',
          'something else entirely',
        ].join('\r\n'),
      )!;

      expect(answer.freeGb, 9);
      expect(answer.processes.map((process) => process.pid), [
        39320,
        50072,
        50073,
      ]);
      expect(answer.processes.map((process) => process.asked), [
        isNull,
        'daemon',
        '',
      ]);
      expect(answer.processes[1].parent, 14296);
      expect(answer.processes[1].born, 200);
    });

    test('free commit is floored — 4GB less one KB is not 4GB', () {
      final answer = windowsAnswerFrom(
        'free\t${4 * 1024 * 1024 - 1}\nproc\t4\t0\t0\t0\tSystem\t',
      )!;

      expect(answer.freeGb, 3);
    });

    test('⛔an answer with no free commit, or with no process, is no '
        'answer', () {
      expect(windowsAnswerFrom('proc\t4\t0\t0\t0\tSystem\t'), isNull);
      expect(windowsAnswerFrom('free\t9437184'), isNull);
      expect(windowsAnswerFrom(''), isNull);
    });

    test('bash\'s table: its own number, its launcher\'s, and the Windows '
        'process the row stands for', () {
      // As `ps -l` printed them; the last row is built by hand — a state
      // letter stands before the number on a stopped process.
      final rows = bashTableFrom(
        '      PID    PPID    PGID     WINPID   TTY         UID    STIME '
        'COMMAND\n'
        '   648237  648136  647956      52528  ?         197609 04:51:59 '
        '/c/Users/gunoo/Documents/flutter/bin/dart.bat\n'
        '   647956       1  647956      48932  ?         197609 04:50:28 '
        '/usr/bin/bash\n'
        'S  621689       1  621689      35176  cons0     197609 04:11:24 '
        '/usr/bin/bash\n',
      );

      expect(
        [for (final row in rows) (row.pid, row.parent, row.winPid)],
        [(648237, 648136, 52528), (647956, 1, 48932), (621689, 1, 35176)],
      );
    });
  });

  test('the turn the tool reads is the turn the lane script holds', () {
    final script = File('tool/lane.sh').readAsStringSync();

    expect(script, contains('--git-common-dir)/$kLandTurn"'));
    expect(script, contains(r'echo "$$" >"$turn/pid"'));
  });
}
