@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show RunTimes, clockAt, cpuSaid, ownClockIn, spanOf;
import '../../tool/process_tree.dart';

/// 🆕2026-11-20 (card the-wide-check-takes-five-hours, 관제 「추측 말고
/// 로그의 시각으로」): the wide check's 11-18 log held each batch's own
/// clock and nothing more — 1:24 of batches in a run of 4:57, and where
/// the rest went could be told only against a line record that names no
/// run. Each batch now says when it started and how long it stood in the
/// line, then its wall time beside its tests' own clock; the run ends with
/// the sums.
void main() {
  group("the runner's own clock", () {
    test('is the latest mm:ss a line begins with before its counter', () {
      const text =
          '00:00 +0: loading test/a_test.dart\n'
          '00:06 +8: test/b_test.dart: a test\n'
          '02:09 +97 ~1: test/c_test.dart: the last one\n'
          '00:15 +9: test/d_test.dart: printed late\n';
      expect(ownClockIn(text), const Duration(minutes: 2, seconds: 9));
    });

    test('runs past an hour as minutes', () {
      expect(
        ownClockIn('61:05 +300 -2: test/e_test.dart: long\n'),
        const Duration(minutes: 61, seconds: 5),
      );
    });

    test('a time inside a line, or a line with no counter, is no clock', () {
      expect(ownClockIn('a test named 12:34 +5: at noon\n'), isNull);
      expect(ownClockIn('12:34 was when it printed\n'), isNull);
      expect(ownClockIn('Warning: a call to drag()\n'), isNull);
    });

    test('a chunk cut inside a line reads earlier, never later', () {
      // `10:15 +9: …` cut after its first digit leaves `0:15 +9: …`.
      expect(
        ownClockIn('0:15 +9: test/f_test.dart: cut\n'),
        const Duration(seconds: 15),
      );
    });
  });

  group('how a time is said', () {
    test('a clock is the hour, minute and second of the day', () {
      expect(clockAt(DateTime(2026, 11, 20, 5, 2, 9)), '05:02:09');
      expect(clockAt(DateTime(2026, 11, 20, 23, 59, 0)), '23:59:00');
    });

    test('a span is m:ss, and h:mm:ss from an hour', () {
      expect(spanOf(const Duration(seconds: 5)), '0:05');
      expect(spanOf(const Duration(minutes: 2, seconds: 43)), '2:43');
      expect(
        spanOf(const Duration(hours: 1, minutes: 35, seconds: 12)),
        '1:35:12',
      );
      expect(spanOf(const Duration(hours: 4, minutes: 5)), '4:05:00');
    });
  });

  test('the run ends with the sums: its batches, their own clocks, what '
      'lay outside them and the wait in line', () {
    final times = RunTimes()
      ..add(
        inLine: const Duration(seconds: 2),
        wall: const Duration(minutes: 2, seconds: 25),
        own: const Duration(minutes: 2, seconds: 9),
      )
      ..add(
        inLine: const Duration(seconds: 40),
        wall: const Duration(minutes: 1, seconds: 45),
        own: null,
      );
    expect(
      times.summary(const Duration(minutes: 5, seconds: 30)),
      'time: 5:30 — 2 batch(es) ran 4:10 (their tests\' own clocks 2:09, '
      'outside them 2:01), 0:42 in line between them',
    );
  });

  group('what else the machine spent beside a batch', () {
    // One second of CPU in GetProcessTimes' 100-nanosecond ticks.
    const second = 10000000;
    ProcessRow row(
      int pid,
      int parent,
      String name, {
      int cpu = 0,
      int born = 1,
    }) => (
      pid: pid,
      parent: parent,
      born: born,
      name: name,
      bytes: 0,
      cpu: cpu * second,
    );

    test("the batch's tree is its own, and the rest is named, most first — "
        'a process born between two looks counted from naught', () {
      final looks = <List<ProcessRow>>[
        [
          row(10, 1, 'flutter.bat', cpu: 1),
          row(11, 10, 'flutter_tester.exe', cpu: 5),
          row(20, 1, 'flutter_tester.exe', cpu: 100),
          row(30, 1, 'rustc.exe', cpu: 7),
        ],
        [
          row(10, 1, 'flutter.bat', cpu: 2),
          row(11, 10, 'flutter_tester.exe', cpu: 65),
          row(12, 10, 'flutter_tester.exe', cpu: 30, born: 5),
          row(20, 1, 'flutter_tester.exe', cpu: 130),
          row(21, 1, 'flutter_tester.exe', cpu: 12, born: 6),
          row(30, 1, 'rustc.exe', cpu: 97),
        ],
      ];
      var i = 0;
      final watch = CpuWatch(
        10,
        read: () => looks[i++ < 1 ? 0 : 1],
        every: const Duration(days: 1),
      );
      final spent = watch.stop();
      // Its own: 1 + 60 + 30 (the tester born after the first look), by
      // name.
      expect(spent.ours, [
        ('flutter_tester.exe', const Duration(seconds: 90)),
        ('flutter.bat', const Duration(seconds: 1)),
      ]);
      expect(cpuOf(spent.ours), const Duration(seconds: 91));
      expect(spent.others, [
        ('rustc.exe', const Duration(seconds: 90)),
        ('flutter_tester.exe', const Duration(seconds: 42)),
      ]);
    });

    test('a process that ended is not counted twice, nor a number come '
        'round again as the old one', () {
      final looks = <List<ProcessRow>>[
        [row(10, 1, 'flutter.bat'), row(40, 1, 'dart.exe', cpu: 50)],
        // 40 ended; a new process took its number.
        [
          row(10, 1, 'flutter.bat'),
          row(40, 1, 'cargo.exe', cpu: 3, born: 9),
        ],
      ];
      var i = 0;
      final spent = CpuWatch(
        10,
        read: () => looks[i++ < 1 ? 0 : 1],
        every: const Duration(days: 1),
      ).stop();
      expect(spent.others, [('cargo.exe', const Duration(seconds: 3))]);
    });

    test("a tester stays the batch's own once the process between it and "
        'the root has ended', () {
      final looks = <List<ProcessRow>>[
        [
          row(10, 1, 'flutter.bat'),
          row(11, 10, 'dart.exe', cpu: 2),
          row(13, 11, 'flutter_tester.exe', cpu: 4),
        ],
        // 11 ended; 13 is an orphan, its parent's number unknown.
        [row(10, 1, 'flutter.bat'), row(13, 11, 'flutter_tester.exe', cpu: 9)],
      ];
      var i = 0;
      final spent = CpuWatch(
        10,
        read: () => looks[i++ < 1 ? 0 : 1],
        every: const Duration(days: 1),
      ).stop();
      expect(spent.ours, [
        ('flutter_tester.exe', const Duration(seconds: 5)),
      ]);
      expect(spent.others, isEmpty);
    });

    test('it is said against the whole machine for the batch\'s wall', () {
      expect(
        cpuSaid(
          (
            ours: [
              ('flutter_tester.exe', const Duration(minutes: 30, seconds: 5)),
              ('dartaotruntime.exe', const Duration(minutes: 8, seconds: 15)),
              ('dart.exe', const Duration(minutes: 3)),
            ],
            others: [
              ('flutter_tester.exe', const Duration(minutes: 20, seconds: 1)),
              ('dart.exe', const Duration(minutes: 9, seconds: 30)),
            ],
          ),
          const Duration(minutes: 2, seconds: 47),
          20,
        ),
        "CPU of the machine's 55:40: its own 41:20 (flutter_tester.exe "
        '30:05 · dartaotruntime.exe 8:15 · dart.exe 3:00), beside it 29:31 '
        '(flutter_tester.exe 20:01 · dart.exe 9:30)',
      );
      expect(
        cpuSaid(
          (ours: const [], others: const []),
          const Duration(seconds: 3),
          20,
        ),
        "CPU of the machine's 1:00: its own 0:00, beside it 0:00",
      );
    });

    test('the table is read with what each process spent, its own work '
        'and the system\'s for it alike', () {
      int mine() => readProcessTable().singleWhere((r) => r.pid == pid).cpu;
      Duration since(int before) =>
          Duration(microseconds: (mine() - before) ~/ 10);
      final before = mine();
      if (!Platform.isWindows) return; // `ps` gives no CPU here: 0.
      // Arithmetic and nothing else, three seconds of the wall between two
      // reads of the table, till it says half a second was spent: user
      // time, which the kernel's share of six table reads (a few tens of
      // milliseconds each, measured 11-20) could never make up.
      // ↩️It was one stretch of a second and a half, and the run's tests
      // stand at Idle: on the Surface under a land's gate that stretch was
      // handed less than a third of a second of the CPU, and the pin went
      // red then green on the same inputs (11-20, flaky card). How long the
      // machine takes to hand it over is not what this pins — but the
      // reads stay few, or their own kernel time would fill the bar alone.
      final busy = Stopwatch()..start();
      var x = 1;
      var spent = Duration.zero;
      for (var read = 0;
          read < 6 && spent < const Duration(milliseconds: 500);
          read++) {
        final step = Stopwatch()..start();
        while (step.elapsedMilliseconds < 3000) {
          x = (x * 31 + 7) & 0xffff;
        }
        spent = since(before);
      }
      expect(x, isNot(-1));
      expect(spent, greaterThanOrEqualTo(const Duration(milliseconds: 500)));
      // One thread cannot spend more of the CPU than the wall it ran — the
      // table's ticks are a hundred nanoseconds, and read as anything else
      // they would be many times this.
      expect(spent, lessThan(busy.elapsed + const Duration(seconds: 1)));
    });
  });

  test('every batch the run launches says its clock, and the run its sums '
      '— where they are said', () {
    // The pieces above are what is said; this is that each is said, in
    // the run's one place a batch starts, ends and the run returns.
    final source = File('tool/affected_tests.dart').readAsStringSync();
    expect(
      source,
      contains(r"— at ${clockAt(began)}, ${spanOf(inLine)} in line'"),
    );
    expect(source, contains('times.add(inLine: inLine, wall: wall, own: own)'));
    expect(
      source,
      contains(r"_report('batch ${i + 1} ran ${spanOf(wall)} — '"),
    );
    expect(
      source,
      contains('_report(times.summary(DateTime.now().difference(started)))'),
    );
    expect(source, contains('ownClock: ownClock,'));
    // In line: from the moment the batch asked the line for its suites to
    // the moment it started.
    expect(source, contains('asked = DateTime.now();'));
    expect(source, contains('final inLine = began.difference(asked);'));
    expect(source, contains('final cpu = CpuWatch(process.pid);'));
    expect(source, contains('spent: spent,'));
    expect(
      source,
      contains(r'${cpuSaid(ran.spent, wall, Platform.numberOfProcessors)}'),
    );
  });
}
