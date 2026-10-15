@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show idleArguments;

/// 🗣️유저 2026-09-24 「PC 굳히지 말 것」: every suite `affected_tests`
/// launches runs at Idle, however the tool itself was launched. 🔬2026-10-15:
/// two runs started straight from a shell, at Normal, starved the user's
/// release build of its AOT compile for five minutes.
///
/// Windows gives an Idle parent's class to everything it launches, so the
/// tool lowering ITSELF before it launches anything is the whole of it.
/// ⛔Not pinned by launching the tool: no test spawns a process
/// (`tests_do_not_race_the_code_test`). What it asks is pinned here, and
/// where it asks is read off its source.
void main() {
  test('the tool asks for Idle for the process it names', () {
    expect(idleArguments(4242), [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "(Get-Process -Id 4242).PriorityClass = 'Idle'",
    ]);
  });

  test('🚨it asks it for itself, before the first process it starts', () {
    final source = File('tool/affected_tests.dart').readAsStringSync();
    final start = source.indexOf('Future<void> main(');
    final firstProcess = source.indexOf('_repoRoot()', start);
    expect(start, isNonNegative);
    expect(firstProcess, greaterThan(start));
    expect(
      source.substring(start, firstProcess),
      contains('_atIdle();'),
      reason: 'git is the first process the tool starts, and every suite '
          'comes after it',
    );
    expect(source, contains("'powershell.exe', idleArguments(pid)"));
  });
}
