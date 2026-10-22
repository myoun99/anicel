import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
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
        if (_timerStartsAt(lines, i)) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
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

  test('premise: the timer scan reads the call whole', () {
    // Its computation five lines down, past where a window of four lines
    // stopped; and a comma that only ends the last argument.
    const late = [
      'Future<void>.delayed(',
      '  const Duration(',
      '    seconds: 0,',
      '    milliseconds: 8,',
      '  ),',
      '  () => landed = true,',
      ');',
    ];
    const plain = [
      'unawaited(Future<void>.delayed(',
      '  const Duration(milliseconds: 8),',
      '));',
    ];
    expect(_timerStartsAt(late, 0), isTrue, reason: late.join());
    expect(_timerStartsAt(plain, 0), isFalse, reason: plain.join());
  });

  test('premise: the poll scan reads a loop past its header', () {
    // A closure in the condition is the condition's, not the loop's block;
    // a `do` opens its block before any call.
    const counted = [
      'for (var t = 0; t < 9 && !seen.any((p) { return p; }); t += 1) {',
      '  await tester.runAsync(() => Future<void>.delayed(beat));',
      '}',
    ];
    const deadline = [
      'do {',
      '  tries.add(1);',
      '  await tester.runAsync(() => Future<void>.delayed(beat));',
      '  if (DateTime.now().isAfter(until)) break;',
      '} while (seen.isEmpty);',
    ];
    expect(_pollStartsAt(counted, 0), isTrue, reason: counted.first);
    expect(_pollStartsAt(deadline, 0), isTrue, reason: deadline.first);
  });

  test('premise: the poll scan reads a header dart format broke either way, '
      'and a count kept in the body', () {
    const alone = [
      'for (',
      '  var t = 0;',
      '  t < 9 && !seen;',
      '  t += 1',
      ') {',
      '  await tester.runAsync(() => Future<void>.delayed(beat));',
      '}',
    ];
    const afterItsFirstClause = [
      'for (var t = 0;',
      '    t < 9 && !seen;',
      '    t += 1) {',
      '  await tester.runAsync(() => Future<void>.delayed(beat));',
      '}',
    ];
    const countedInItsBody = [
      'for (var t = 1; ; t += 1) {',
      '  if (seen || t == 9) return;',
      '  await Future<void>.delayed(beat);',
      '}',
    ];
    for (final loop in [alone, afterItsFirstClause, countedInItsBody]) {
      final read = _headersOnOneLine(loop);
      expect(read, hasLength(loop.length), reason: 'each line keeps its place');
      expect(_pollStartsAt(read, 0), isTrue, reason: loop.first);
    }
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
  /// its own or does nothing but wait. 🔬On master `2d410f381` this named
  /// 128 — 26 · 54 · 23 · 25, the forms in that order — every one a wait
  /// for something to come. Five of them stood in a header dart format
  /// broke over lines, which a loop's own line alone never shows
  /// ([_headersOnOneLine]): read line by line, the scan had passed them.
  /// 🔬On master `243dd8074` it passed four more: three in a header broken
  /// after its first clause, and one that kept its count in its body.
  ///
  /// ⛔A WINDOW is rounds on purpose — given to see that something does NOT
  /// happen, it must not see less on a busy machine (`lendBothClocks`) —
  /// and it never leaves early. Leaving early is what gives a poll away.
  test('no test polls in a loop of its own', () {
    // The loops that look like a test's own poll and are not one.
    const pollsOnPurpose = [
      // The poll every test waits through — its one home.
      'poll_until.dart',
      // The poll a wait on a device's own run goes through: the device
      // keeps the time, not the wall (its head says why), and a take's
      // 600 ms is what the device handed, counted there.
      'device_paced.dart',
    ];
    final offenders = <String>[];
    for (final file in testFiles()) {
      if (pollsOnPurpose.any(file.path.endsWith)) {
        continue;
      }
      final lines = _headersOnOneLine(file.readAsLinesSync());
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
      final lines = _headersOnOneLine(file.readAsLinesSync());
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

  test('premise: the ceiling scan sees both doors, and not the one wait', () {
    const doors = [
      'await whole.timeout(const Duration(seconds: 30));',
      '.timeout(const Duration(seconds: 10), onTimeout: () {});',
      'patience: const Duration(seconds: 30),',
    ];
    for (final line in doors) {
      expect(_ownCeiling(line), isTrue, reason: line);
    }
    const notOne = ['await patiently(whole);', '// .timeout( in a comment'];
    for (final line in notOne) {
      expect(_ownCeiling(line), isFalse, reason: line);
    }
  });

  /// 🚨**A FUTURE IS AWAITED AT THE ONE CEILING TOO** (card
  /// `a-test-awaits-a-future-with-a-ceiling-of-its-own`). What waits for
  /// something to come waits by `waitPatience`, a poll as much as a future,
  /// and `patiently` (`poll_until.dart`) is a future's. A `.timeout(` of a
  /// test's own is the copy with a number of its own — ten seconds, or
  /// thirty — and four of them went on when it ran out (`onTimeout: () {}`),
  /// so a walk still at work read as one at rest. A `patience:` handed to a
  /// wait is the same number through another door. 🔬On the poll lane's tip
  /// (`578d25152`) this named 13 — twelve `.timeout(` and one `patience:`.
  test('no test waits with a ceiling of its own', () {
    // The ceilings that are not a wait for something to come.
    const notAWait = [
      // The one ceiling's home.
      'helpers/poll_until.dart',
      // The watch on a stuck native call: its limits are what it measures —
      // a step stood past its limit, a dump that must end — and its own
      // test holds the watch to them.
      'helpers/native_call_watch.dart',
      'helpers/a_stuck_native_call_is_named_test.dart',
      // The run's end: what it left is asked until the run's own deadline,
      // and the test of that asks at once.
      'helpers/temp_dir.dart',
      'architecture/a_test_run_leaves_its_temp_empty_test.dart',
    ];
    final offenders = <String>[];
    for (final file in testFiles()) {
      final path = file.path.replaceAll(r'\', '/');
      if (notAWait.any(path.endsWith)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (_ownCeiling(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these wait with a number of their own. Await a future with '
          'patiently, and let a poll wait by waitPatience.',
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

/// Whether [line] gives a wait a ceiling of its own: a future's `.timeout(`
/// or a poll's `patience:`. A comment only names them.
bool _ownCeiling(String line) {
  final trimmed = line.trim();
  return !trimmed.startsWith('//') &&
      (trimmed.contains('.timeout(') || trimmed.contains('patience:'));
}

/// Whether a timer left unawaited starts at [lines]' [at]: a `.delayed(…)`
/// that hands the clock a computation, read whole however many lines it
/// runs over.
bool _timerStartsAt(List<String> lines, int at) {
  final line = lines[at];
  if (!line.contains('.delayed(')) {
    return false;
  }
  // `await Future.delayed(d)` just waits — the test is not running while it
  // does, so nothing can race it. What bites is the two-arg form left
  // unawaited: it hands work to the clock and carries on.
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('await ') ||
      trimmed.startsWith('//') ||
      trimmed.startsWith('///') ||
      line.contains('=> Future') ||
      line.contains('return Future')) {
    return false;
  }
  return _delayedTakesAComputation(lines.sublist(at).join('\n'));
}

/// Whether a `.delayed(…)` call passes a SECOND argument — the computation
/// that makes it a scheduled side effect rather than a plain wait.
///
/// 🚨Reads the call's arguments by their brackets instead of matching a
/// pattern. The first version used `\.delayed\([^)]*,` and that stops at the
/// first `)`, which on the real call — `.delayed(const Duration(milliseconds:
/// 8), () {…})` — is the one closing `Duration`. It found nothing and
/// reported green; a mutation that put the old bug back is what showed it.
/// ↩️It counted the parentheses itself, in a window of four lines, and a
/// comma that only ends the last argument read as a second one. The call is
/// read whole, by the one reading ([callArguments]).
bool _delayedTakesAComputation(String source) {
  final at = source.indexOf('.delayed(');
  if (at < 0) {
    return false;
  }
  final arguments = callArguments(source, at + '.delayed'.length);
  return arguments != null && arguments.length > 1;
}

/// A counted `for` loop's own line — `for (var i = 0; i < n; …)`, or one
/// that keeps its count in its body (`for (var i = 0; ; …)`). ↩️The second
/// passed by until 2026-10-19: the import tests' retry of a mapped file
/// gave up on its fiftieth try that way.
final _countedLoop = RegExp(r'^\s*for \(var \w+ = \d+; (\w+ < |;)');

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
/// Reads the loop's block by its braces, as [_delayedTakesAComputation]
/// reads its call by its parentheses — not a window of so many lines, which
/// would read a long loop short and a short one into whatever follows it.
/// The block opens past the loop's header — on its own line, or in the one
/// statement after it (`foo(() {`); the one reading says where it closes
/// ([matchingClose]). A brace inside the header (`any((p) { … })`) is the
/// condition's, not the block's.
List<String> _loopAt(List<String> lines, int at) {
  final next = (at + 2).clamp(0, lines.length);
  final head = lines.sublist(at, next).join('\n');
  final open = codeIndexOf(head, '{', _pastHeader(head));
  if (open == null) {
    return lines.sublist(at, next);
  }
  final rest = lines.sublist(at).join('\n');
  final close = matchingClose(rest, open);
  if (close == null) {
    return lines.sublist(at);
  }
  final last = at + '\n'.allMatches(rest.substring(0, close)).length;
  return lines.sublist(at, last + 1);
}

/// Where the header a `for` or a `while` opens with ends in [head] — just
/// past its `(…)` — or 0 for a `do`, whose block comes first.
int _pastHeader(String head) {
  final paren = codeIndexOf(head, '(');
  final brace = codeIndexOf(head, '{');
  if (paren == null || (brace != null && brace < paren)) {
    return 0;
  }
  final close = matchingClose(head, paren);
  return close == null ? head.length : close + 1;
}

/// [lines] with each loop header dart format broke over lines read as one
/// line on its first, and the lines it took left blank, so every line
/// keeps its number. A loop's own line is where every scan here looks for
/// its count and its condition, and a broken header shows neither there.
///
/// Read by its brackets ([matchingClose]), as the loop's block is: dart
/// format breaks a header two ways — `for (` alone, its clauses, then
/// `) {`; or after its first clause (`for (var i = 0;`), the rest beneath
/// it. ↩️It knew only the first until 2026-10-19, and three polls of the
/// import and open tests stood in the second (card
/// `import-wait-tests-read-the-wall-clock`).
List<String> _headersOnOneLine(List<String> lines) {
  final joined = [...lines];
  for (var i = 0; i < joined.length; i += 1) {
    final header = _loopHeader.firstMatch(joined[i]);
    if (header == null || matchingClose(joined[i], header.end - 1) != null) {
      continue;
    }
    final rest = joined.sublist(i).join('\n');
    final close = matchingClose(rest, header.end - 1);
    if (close == null) {
      continue;
    }
    final end = i + '\n'.allMatches(rest.substring(0, close)).length;
    for (var j = i + 1; j <= end; j += 1) {
      joined[i] = _readOn(joined[i], joined[j].trim());
      joined[j] = '';
    }
  }
  return joined;
}

/// A loop's own line, to the bracket its header opens.
final _loopHeader = RegExp(r'^\s*(for|while) \(');

/// [line] with [next] read on after it — straight on past a bracket that
/// opens or before one that closes, and past a space between two clauses.
String _readOn(String line, String next) =>
    line.endsWith('(') || next.startsWith(')') ? '$line$next' : '$line $next';
