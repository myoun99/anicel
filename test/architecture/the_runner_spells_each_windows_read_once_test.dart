import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ledger.dart';

/// 🚨THE WINDOWS RUNNER SPELLS EACH OF THESE ONCE, IN `utils.cpp`: a text
/// turned from UTF-8 to UTF-16 and back (`Utf16FromUtf8`,
/// `Utf8FromUtf16`), and the path of the executable a process runs
/// (`ExecutableOf`).
///
/// The splash and `main.cpp` each wrote their own UTF-16 turn till the lost
/// screen's channel made a third (2026-11-18, board
/// a-lost-gpu-leaves-the-window-unpainted); the splash and the restart each
/// read their own path till the handover asked another process's
/// (a-launch-with-a-file-joins-whatever-anicel-runs-Q1, 2026-11-18). Two
/// paths of one file compared are read by the one call, or one spelling of
/// them can miss the other.
///
/// ⛔A behaviour test cannot hold this — this suite runs no runner, and two
/// copies that agree pass any of them — so the source is scanned.
void main() {
  test('no runner file but utils.cpp calls the Windows API these are '
      'spelled with', () {
    final calls = RegExp(
      r'\b(MultiByteToWideChar|WideCharToMultiByte|GetModuleFileName\w*|'
      r'QueryFullProcessImageName\w*)\s*\(',
    );
    final found = <String>[];
    for (final file in Directory('windows/runner').listSync()) {
      final name = file.uri.pathSegments.last;
      if (file is! File ||
          !(name.endsWith('.cpp') || name.endsWith('.h')) ||
          name == 'utils.cpp') {
        continue;
      }
      final code = codeOfLines(file.readAsStringSync());
      for (final (index, line) in code.split('\n').indexed) {
        if (calls.hasMatch(line)) {
          found.add('windows/runner/$name:${index + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      found,
      isEmpty,
      reason:
          'ask utils.h — Utf16FromUtf8, Utf8FromUtf16 or ExecutableOf — '
          'in place of the call',
    );
  });

  test('utils.cpp still spells each, and the scan sees a call and not one '
      'named in a comment', () {
    final code = codeOfLines(
      File('windows/runner/utils.cpp').readAsStringSync(),
    );
    for (final call in [
      'MultiByteToWideChar(',
      'WideCharToMultiByte(',
      'QueryFullProcessImageNameW(',
    ]) {
      expect(code, contains(call));
    }
    expect(
      codeOfLines('// GetModuleFileNameW(nullptr, self, MAX_PATH)'),
      isNot(contains('GetModuleFileNameW')),
    );
  });
}
