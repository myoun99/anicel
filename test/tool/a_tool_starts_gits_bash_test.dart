import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bash_executable.dart';

/// 🚨A tool that starts bash starts the one PATH names, not Windows' own.
///
/// ⛔2026-10-24: the bundle PR's Windows shard went red on
/// `a_source_scan_runs_when_what_it_reads_changes_test` — `parityTests()`
/// answered null. It started a bare `bash`, which Windows looks for in its
/// own folder before PATH; GitHub's runner keeps WSL's launcher there
/// (`System32\bash.exe`, no Linux installed, so it only fails). The main PC
/// has no launcher, so the wide check there was green.
void main() {
  const windows = r'C:\Windows';
  const git = r'C:\Program Files\Git\usr\bin';
  const launcher = r'C:\Windows\System32\bash.exe';
  const gits = r'C:\Program Files\Git\usr\bin\bash.exe';

  bool onDisk(String path) => path == launcher || path == gits;

  test("🚨Git's bash, even when the Windows folder comes first on PATH", () {
    expect(
      bashOnPath(
        [r'C:\Windows\System32', windows, git],
        windowsFolder: windows,
        exists: onDisk,
      ),
      gits,
    );
  });

  test('the first bash on PATH, as a shell would start it', () {
    const other = r'D:\msys64\usr\bin';
    bool both(String path) => onDisk(path) || path == '$other\\bash.exe';
    expect(
      bashOnPath([other, git], windowsFolder: windows, exists: both),
      '$other\\bash.exe',
    );
    expect(
      bashOnPath(['$git\\', other], windowsFolder: windows, exists: both),
      gits,
      reason: 'a folder written with its trailing backslash',
    );
  });

  test('no bash on PATH but the launcher — a bare `bash`, as before', () {
    expect(
      bashOnPath(
        [r'C:\Windows\System32', ''],
        windowsFolder: windows,
        exists: onDisk,
      ),
      'bash',
    );
  });

  test('⛔no tool starts a bare `bash` — they ask `bashExecutable`', () {
    final bare = RegExp(r"Process\.(start|run|runSync)\(\s*'bash'");
    final starts = [
      for (final file in Directory('tool').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            bare.hasMatch(file.readAsStringSync()))
          file.path.replaceAll(r'\', '/'),
    ];
    expect(starts, isEmpty);
  });
}
