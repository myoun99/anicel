import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️play-auto-upload (유저 2026-10-31 「지금 빌드시 자동으로 올리는것도
/// 할수있나? 플레이스토어쪽?」): `tool/play_upload.sh` publishes a bundle on
/// the closed test. Only the control tower's round runs it and a wrong step
/// reaches testers, so what it must not get wrong is read here. No test may
/// start it (`tests_do_not_race_the_code_test`): 📏it ran against a stand-in
/// for Google when written, every step in this order and each refusal
/// stopping there.
void main() {
  final script = File('tool/play_upload.sh').readAsStringSync();

  int at(String step) {
    final found = script.indexOf(step);
    expect(found, isNonNegative, reason: step);
    return found;
  }

  const checkBranch = r'if [ "$mode" = --check ]';

  test('it uploads, names the release and validates before it publishes', () {
    final steps = [
      "'uploading the bundle'",
      "'naming the release'",
      "'validating the edit'",
      checkBranch,
      "'publishing'",
    ].map(at).toList();
    expect(steps, orderedEquals(steps.toList()..sort()));
  });

  test('--check throws the edit away and leaves before publishing', () {
    final branch = script.substring(at(checkBranch), at("'publishing'"));
    expect(branch, contains("'throwing the edit away'"));
    expect(branch, contains('exit 0'));
  });

  test('the release goes to every tester of the closed test, and no further',
      () {
    expect(script, contains(RegExp(r'^track=alpha\s*$', multiLine: true)));
    expect(script, contains(r'\"status\":\"completed\"'));
    expect(script, contains(r'\"versionCodes\":[\"$number\"]'));
    expect(script, contains(r'\"name\":\"$number ($version)\"'));
  });

  test('the key it writes out to sign with goes when the script does', () {
    expect(script, contains(r'''trap 'rm -rf "$work"' EXIT'''));
  });

  test("a refused step stops the script, in Play's own words", () {
    expect(script, contains('--fail-with-body'));
    expect(script, contains(r'|| die "$what: $body"'));
  });
}
