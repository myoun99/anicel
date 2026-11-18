import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ledger.dart' show codeOfLines;

/// 🚨THE GROUND A NEW PROJECT IS MADE ON IS READ BEFORE THE FIRST ONE IS
/// MADE.
///
/// Board the-first-untitled-project-misses-the-saved-ground-colour
/// (2026-11-16): a project COPIES the ground the settings hold as it is
/// made (`newUntitledProject`), and the launch's untitled project is made
/// as the home page starts — before the session's restore had read the
/// saved ground. 🔬Measured with the profile app on Windows: saved
/// ff2e7d32, the launch's project wore the built-in ff141517 and every
/// later one the saved. main now awaits the read before it runs the app,
/// as it does the language. No test runs a launch, so it is read from the
/// source.
void main() {
  test('main awaits the saved ground before it runs the app', () {
    final source = codeOfLines(File('lib/main.dart').readAsStringSync());
    final read = RegExp(
      r'AppWorkspaceColors\.settings\.value =\s+'
      r'await AppWorkspaceColorsStore\(\)\.load\(\) \?\?\s+'
      r'const AppWorkspaceColors\(\);',
    ).firstMatch(source);
    final run = source.indexOf('runApp(');

    expect(run, greaterThan(0), reason: '⛔premise: the app is run');
    expect(read, isNotNull, reason: 'the saved ground, else the built-in');
    expect(read!.end, lessThan(run));
  });
}
