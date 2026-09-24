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
    final offenders = <String>[];
    for (final file in testFiles()) {
      if (scannersNotSpawners.any(file.path.contains)) {
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
