import 'package:flutter_test/flutter_test.dart';

import '../../tool/bash_executable.dart';
import '../helpers/dart_sources.dart';

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

  group("a PATH with no bash but WSL's alias (2026-11-23)", () {
    // The alias is not on disk to Dart — a link it does not take for a
    // file; a bare `bash` is what reached it, through Windows' own lookup.
    const aliases = r'C:\Users\u\AppData\Local\Microsoft\WindowsApps';
    const gitCmd = r'C:\Program Files\Git\cmd';
    const gitMingw = r'C:\Program Files\Git\mingw64\bin';
    const gitsShortcut = r'C:\Program Files\Git\bin\bash.exe';
    bool installed(String path) =>
        onDisk(path) ||
        path == '$gitCmd\\git.exe' ||
        path == '$gitMingw\\git.exe' ||
        path == gitsShortcut;

    test("🚨PowerShell's PATH: the bash of the Git install whose git it "
        'names, not a bare `bash`', () {
      expect(
        bashOnPath(
          [r'C:\Windows\System32', gitCmd, aliases, gitMingw],
          windowsFolder: windows,
          exists: installed,
        ),
        gitsShortcut,
      );
      expect(
        bashOnPath(
          [aliases, gitMingw],
          windowsFolder: windows,
          exists: installed,
        ),
        gitsShortcut,
        reason: "git named only from the install's mingw64\\bin",
      );
    });

    test('a bash on PATH still comes before the git walk', () {
      expect(
        bashOnPath(
          [gitCmd, git],
          windowsFolder: windows,
          exists: installed,
        ),
        gits,
      );
    });

    test('no git either — a bare `bash`, as before', () {
      expect(
        bashOnPath(
          [r'C:\Windows\System32', aliases],
          windowsFolder: windows,
          exists: installed,
        ),
        'bash',
      );
    });
  });

  test('⛔no tool starts a bare `bash` — they ask `bashExecutable`; a start '
      'through the shell keeps it', () {
    // Through the shell cmd walks PATH itself, and cuts a quoted path with a
    // space (the board's relaunch, 2026-10-24).
    // Any call handed `bash` first — `Process` or a tool's own wrapper.
    final bare = RegExp(r"\(\s*'bash'\s*,[^;]*");
    final starts = [
      for (final file in dartFilesUnder('tool'))
        for (final call in bare.allMatches(file.readAsStringSync()))
          if (!call[0]!.contains('runInShell: true'))
            file.path.replaceAll(r'\', '/'),
    ];
    expect(starts, isEmpty);
  });
}
