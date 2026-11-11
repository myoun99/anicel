import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 관제 2026-11-11 (fill-runs-in-the-c-engine's first commit): two of the
/// C's exports had no caller in the app — `qa_tile_alpha_bounds` bound by
/// nothing, `qa_premultiply_rgba` bound and never called — and four were
/// exported for the C's own batches alone. What the C exports is what the
/// app looks up by name, and no more: an export is a door a kernel of the
/// C's can be reached by, and the C is on its way out (C 0줄).
void main() {
  test('every function the C exports is one the app looks up by name', () {
    final c = File('packages/qa_native/src/qa_engine.c').readAsStringSync();
    final exported = {
      for (final match in RegExp(
        r'^QA_EXPORT\s[^(;]*?\b(qa_\w+)\s*\(',
        multiLine: true,
      ).allMatches(c))
        match.group(1)!,
    };
    expect(exported, isNotEmpty, reason: '⛔premise: the scan finds them');

    final app = [
      for (final file in dartFilesUnder('lib')) file.readAsStringSync(),
    ].join('\n');
    expect([
      for (final name in exported)
        if (!app.contains("'$name'")) name,
    ], isEmpty);
  });
}
