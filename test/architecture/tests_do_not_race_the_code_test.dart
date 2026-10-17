import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨★★★**A TEST MUST NOT SCHEDULE ITS DATA ON A WALL CLOCK.**
///
/// The gate went intermittently red twice, and both times the product was
/// fine and the TEST was racing it:
///
/// • `materialize_opened_file_test` landed a file's bytes on an 8 ms timer
///   while the code polled every 1 ms. Under a bulk run that timer could
///   fire BEFORE the first probe — and a file that is already readable is
///   correctly opened without asking, so the assertion「asked == 1」failed
///   for a reason that had nothing to do with the code (#1362).
/// • `board_check_test` spawned 24 subprocesses that competed with the rest
///   of the suite for the machine (#1361).
///
/// 🚨**A THIRD SHAPE, WHICH NOTHING BELOW SCANS FOR — read it, because
/// only a reader can catch it: DECIDING SOMETHING FINISHED BY OBSERVING
/// THAT NOTHING HAPPENED.**
///
/// `timeline_viewport_resize_test` waited for its raster queue to converge
/// by breaking out of a poll loop when the store's revision had not moved
/// in the last 50ms. On the machine it was written on that reads「the
/// drains are done」. On a machine running the whole suite it reads「the
/// drains have not STARTED」 just as often — so the loop exited early,
/// probed a cold store, and the file went red in bulk runs while passing
/// alone.
///
/// ⛔The two mechanical scanners below cannot see this: the delay is
/// awaited and single-argument, which is the FORM they call safe. What
/// makes it a race is what the test CONCLUDES from the delay.
///
/// ✅Wait for positive evidence — loop WHILE the thing has not happened,
/// or accept silence only AFTER a landing has been seen. Silence before
/// the first landing means nothing at all.
///
/// ⛔The fix is never a longer delay. A delay tuned on an idle machine is a
/// bet on how busy the machine will be, and the bulk run is exactly when it
/// is busiest. Cause the event instead: write the bytes INSIDE the fake the
/// code calls, so the arrival happens BECAUSE the code asked.
///
/// 🚨This scans the SOURCE, because a race that only appears under load is
/// precisely what a behaviour test cannot catch — it passes on the machine
/// you write it on, which is how both of these reached master.
void main() {
  /// Every test file except THIS one.
  ///
  /// ⛔A scanner that reads its own source finds the patterns it is looking
  /// for spelled out in its own matcher — the first version of this file
  /// failed on exactly that. Excluding itself is not a loophole: there is
  /// nothing here to race, and the alternative (spelling the patterns some
  /// obfuscated way so they do not match) hides the rule from whoever reads
  /// it next.
  Iterable<File> testFiles() sync* {
    for (final entity in dartFilesUnder('test')) {
      if (entity.path.endsWith('tests_do_not_race_the_code_test.dart')) {
        continue;
      }
      yield entity;
    }
  }

  test('no test schedules a side effect on an unawaited timer', () {
    final offenders = <String>[];
    for (final file in testFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (!line.contains('.delayed(')) {
          continue;
        }
        // `await Future.delayed(d)` just waits — the test is not running
        // while it does, so nothing can race it. What bites is the two-arg
        // form left unawaited: it hands work to the clock and carries on.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('await ') ||
            trimmed.startsWith('//') ||
            trimmed.startsWith('///') ||
            line.contains('=> Future') ||
            line.contains('return Future')) {
          continue;
        }
        final tail = lines.sublist(i, (i + 4).clamp(0, lines.length)).join(' ');
        if (_delayedTakesAComputation(tail)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these hand a side effect to the wall clock and hope it lands in '
          'the right order. Cause it from inside the seam the code calls '
          'instead — see the doc above this test.',
    );
  });

  /// 🚨**A POLL WAITS BY THE CLOCK, NOT BY A COUNT OF ROUNDS** (card
  /// `a-poll-that-counts-rounds-runs-out-under-load`). A loop that lends
  /// real time a fixed number of times and leaves the moment what it waits
  /// for is there is bounded by how many rounds fit, and under load a round
  /// takes longer: the settings round trip and the Drive save went red that
  /// way and passed alone. ✅`settleAsync` and `pollUntil` (`test/helpers/`)
  /// wait by `waitPatience`; a loop of a test's own is the copy coming back
  /// in one of four forms — counted, leaving by its body or by its own
  /// condition (`i < n && !landed()`), or a `while` that keeps a deadline of
  /// its own or does nothing but wait. 🔬On master `4520fe717` this named
  /// 124 — 27 · 49 · 23 · 25, the forms in that order — every one a wait
  /// for something to come.
  ///
  /// ⛔A WINDOW is rounds on purpose — given to see that something does NOT
  /// happen, it must not see less on a busy machine (`lendBothClocks`) —
  /// and it never leaves early. Leaving early is what gives a poll away.
  test('no test polls in a loop of its own', () {
    // The loops that look like a test's own poll and are not one.
    const pollsOnPurpose = [
      // The poll every test waits through — its one home.
      'poll_until.dart',
      // A take on the null device rolls in real time: the 600 ms it is
      // given is what the microphone takes in, ticked, not a wait for
      // anything to come.
      'a_take_lands_by_what_was_heard_test.dart',
    ];
    final offenders = <String>[];
    for (final file in testFiles()) {
      if (pollsOnPurpose.any(file.path.endsWith)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (_pollStartsAt(lines, i)) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these wait for something in a loop of their own — a count of '
          'rounds runs out under load, and a deadline of their own is the '
          'same guess. Wait with settleAsync or pollUntil, which wait by '
          'waitPatience.',
    );
  });

  /// ⛔**A WINDOW HAS ONE HOME TOO** — `lendBothClocks`, which says why it
  /// is rounds. A counted loop that lends real time and pumps and does
  /// nothing else is its copy: the landing waits four times over and a
  /// `_settle` twice were that, each with a count and a beat of its own.
  /// 🔬On master `4520fe717` this named 27.
  test('no test lends both clocks in a window of its own', () {
    final offenders = <String>[];
    for (final file in testFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (_windowStartsAt(lines, i)) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these lend both clocks a count of rounds in a loop of their own. '
          'Give the window with lendBothClocks.',
    );
  });

  test('no test spawns a process — the bulk run is the wrong place to '
      'compete for the machine', () {
    const spawns = ['Process.run', 'Process.start', 'Process.runSync'];
    // ⚠️A test that SCANS for these names is not a test that calls them.
    // `the_report_names_only_fallbacks_that_exist_test` keeps the System
    // panel from advertising an ffmpeg audio path that was deleted, and the
    // only way to ask 「does anything start a process here?」 is to hold the
    // words. Excluded by NAME rather than by a comment trick, so the
    // exception is visible and has to be argued for.
    //
    // ⛔Only for THIS law — the file is still held to every other one.
    const scannersNotSpawners = ['the_report_names_only_fallbacks_that_exist'];
    // 🗣️The ONE process a test may start (Q1, 유저 2026-10-16: 「예외 하나 —
    // 감시가 멈춤을 본 뒤 한 번만, 바깥에서 덤프」): the native call watch
    // starts the SDK's dart once, after a step has stood past its limit, to
    // dump the stuck process from outside it — as a minidump has to be
    // written. By then the run is lost, so it competes with nothing (board
    // the-trimmed-movie-test-can-hang-on-windows-ci-Q1).
    const dumpsTheLostRun = ['native_call_watch.dart'];
    final offenders = <String>[];
    for (final file in testFiles()) {
      if (scannersNotSpawners.any(file.path.contains) ||
          dumpsTheLostRun.any(file.path.endsWith)) {
        continue;
      }
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
          continue;
        }
        if (spawns.any(trimmed.contains)) {
          offenders.add('${file.path}: $trimmed');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a subprocess per case turns a fast suite into a fight for cores, '
          'and the losers time out (#1361 took 24 of them to 0). Call the '
          'thing in-process.',
    );
  });
}

/// Whether a `.delayed(…)` call passes a SECOND argument — the computation
/// that makes it a scheduled side effect rather than a plain wait.
///
/// 🚨Counts parentheses instead of matching a pattern. The first version
/// used `\.delayed\([^)]*,` and that stops at the first `)`, which on the
/// real call — `.delayed(const Duration(milliseconds: 8), () {…})` — is the
/// one closing `Duration`. It found nothing and reported green; a mutation
/// that put the old bug back is what showed it.
bool _delayedTakesAComputation(String source) {
  final at = source.indexOf('.delayed(');
  if (at < 0) {
    return false;
  }
  var depth = 0;
  for (var i = at + '.delayed'.length; i < source.length; i += 1) {
    final char = source[i];
    if (char == '(') {
      depth += 1;
    } else if (char == ')') {
      depth -= 1;
      if (depth == 0) {
        return false; // Closed with one argument: a plain wait.
      }
    } else if (char == ',' && depth == 1) {
      return true; // A second argument at the call's own level.
    }
  }
  return false; // Unbalanced within the window — not a claim either way.
}

/// A counted `for` loop's own line — `for (var i = 0; i < n; …)`.
final _countedLoop = RegExp(r'^\s*for \(var \w+ = \d+; \w+ < ');

/// A `while` loop's own line, or a `do` loop's.
final _openLoop = RegExp(r'^\s*(while \(|do \{)');

/// A line that lends real time: a test's `runAsync`, or a plain delay.
final _lendsRealTime = RegExp(r'runAsync\(|\.delayed\(');

/// A line that leaves a counted loop before its count is up — a `break`, a
/// `return`, or the loop's own condition asking for more than the count.
final _leavesEarly = RegExp(
  r'\bbreak;|\breturn\b|^\s*for \(var \w+ = \d+; \w+ < [^;]*&&',
);

/// A line that reads the wall clock — a deadline of a loop's own.
final _readsTheClock = RegExp(r'DateTime\.now\(\)|Stopwatch|\.elapsed\b');

/// A line of a loop's body that does nothing but wait: time lent and the
/// closure it is lent through, a pump, a re-read of what is waited for, a
/// closing bracket, a comment.
final _onlyWaits = RegExp(
  r'^\s*(await (Future<void>|Future|tester)\.'
  r'(delayed|pump|pumpAndSettle|runAsync)\b.*'
  r'|\(\) (async )?(=>|\{).*'
  r'|\w+ = [^;]*;'
  r'|[})\];,]*'
  r'|//.*)$',
);

/// Whether a loop that waits for something to come starts at [lines]'
/// [at]: one that lends real time and leaves once it has come — counted,
/// by its body or by its own condition — or a `while` / `do` that keeps a
/// deadline of its own or does nothing but wait.
bool _pollStartsAt(List<String> lines, int at) {
  final counted = _countedLoop.hasMatch(lines[at]);
  if (!counted && !_openLoop.hasMatch(lines[at])) {
    return false;
  }
  final loop = _loopAt(lines, at);
  if (!loop.any(_lendsRealTime.hasMatch)) {
    return false;
  }
  if (counted) {
    return loop.any(_leavesEarly.hasMatch);
  }
  return loop.any(_readsTheClock.hasMatch) ||
      _bodyOf(loop).every(_onlyWaits.hasMatch);
}

/// A line that turns a widget test's pumped clock.
final _pumps = RegExp(r'tester\.pump\(');

/// Whether a window of a test's own starts at [lines]' [at]: a counted
/// loop that lends both clocks — real time and a pump — does nothing else,
/// and never leaves early.
bool _windowStartsAt(List<String> lines, int at) {
  if (!_countedLoop.hasMatch(lines[at])) {
    return false;
  }
  final loop = _loopAt(lines, at);
  return loop.any(_lendsRealTime.hasMatch) &&
      loop.any(_pumps.hasMatch) &&
      !loop.any(_leavesEarly.hasMatch) &&
      _bodyOf(loop).every(_onlyWaits.hasMatch);
}

/// The lines between a loop's own line and the brace that closes it — or
/// its one statement, when it has no block.
List<String> _bodyOf(List<String> loop) =>
    loop.length > 2 ? loop.sublist(1, loop.length - 1) : loop.sublist(1);

/// The lines of the loop that starts at [lines]' [at] — its own line to the
/// brace that closes its block, or to its one statement when it has no
/// block.
///
/// Reads the loop's block by counting braces, as
/// [_delayedTakesAComputation] counts parentheses — not a window of so
/// many lines, which would read a long loop short and a short one into
/// whatever follows it.
List<String> _loopAt(List<String> lines, int at) {
  var depth = 0;
  var opened = false;
  for (var i = at; i < lines.length; i += 1) {
    for (final unit in lines[i].codeUnits) {
      if (unit == 0x7B) {
        depth += 1;
        opened = true;
      } else if (unit == 0x7D) {
        depth -= 1;
      }
    }
    if (opened ? depth <= 0 : i > at) {
      return lines.sublist(at, i + 1);
    }
  }
  return lines.sublist(at);
}
