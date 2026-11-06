import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨THE CRATES WRITTEN HERE ARE FUZZED WITH THEIR TESTS' CHECKS; THE
/// CRATES.IO ONES AS THE APP BUILDS THEM.
///
/// 🗣️native-memory-safety-Q1 (유저 2026-11-06): cargo-fuzz turns debug
/// assertions on in every crate unless it is given `-O`, and the audio
/// target stopped within seconds, every time, at an overflow inside
/// symphonia that the app's release build of the engine wraps. So the job
/// builds as the app does (`-O`), and the fuzz crate's manifest turns the
/// checks back on for each crate of this repository it reads. A path
/// dependency added without its section would be fuzzed unchecked, and
/// nothing else would say so.
///
/// ⚠️BOTH LINES: `debug-assertions = true` alone reaches rustc beside the
/// release profile's `overflow-checks=off`, and the overflow checks stay
/// off (measured with `cargo build -v`, 2026-11-06).
void main() {
  const manifest = 'packages/gpu_engine/rust/fuzz/Cargo.toml';
  const workflow = '.github/workflows/fuzz.yml';

  test('every crate of this repository the fuzz crate reads keeps both '
      'checks, and so does the fuzz crate', () {
    final text = File(manifest).readAsStringSync();
    final ours = [
      for (final match in RegExp(
        r'^(\w+) = \{ path = "\.\./native/',
        multiLine: true,
      ).allMatches(text))
        match.group(1)!,
    ];
    expect(ours, isNotEmpty, reason: manifest);
    final unchecked = [
      for (final name in [...ours, 'decoder_fuzz'])
        if (!_keepsBothChecks(text, name)) name,
    ];
    expect(
      unchecked,
      isEmpty,
      reason:
          '[profile.release.package.<name>] with debug-assertions = true '
          'and overflow-checks = true',
    );
  });

  test('and the job builds every other crate as the app does', () {
    final runs = [
      for (final line in File(workflow).readAsLinesSync())
        if (!line.trim().startsWith('#') && line.contains('fuzz run')) line,
    ];
    expect(runs, hasLength(1), reason: workflow);
    expect(runs.single, contains(' -O '));
    expect(runs.single, isNot(contains('--debug-assertions')));
  });
}

/// Whether [text] has a `[profile.release.package.<name>]` section that
/// turns both checks on.
bool _keepsBothChecks(String text, String name) {
  final lines = text.split(RegExp(r'\r?\n'));
  final start = lines.indexOf('[profile.release.package.$name]');
  if (start < 0) {
    return false;
  }
  final body = lines.skip(start + 1).takeWhile((line) => !line.startsWith('['));
  return body.contains('debug-assertions = true') &&
      body.contains('overflow-checks = true');
}
