import 'dart:io';

/// The bash a tool starts: on Windows, the first `bash.exe` on PATH outside
/// the Windows folder — else Git's own, beside the git on PATH; elsewhere,
/// or when there is neither, `bash`.
///
/// ⚠️Windows starts a bare `bash` from its own folder before it looks at
/// PATH, and `System32\bash.exe` there is WSL's launcher, not a shell: with
/// no Linux distribution installed it only fails. GitHub's Windows runners
/// carry it — 2026-10-24 `parityTests` answered null on the runner and green
/// on the main PC, which has no launcher. A shell asked for `bash` walks
/// PATH, and that is the bash the scripts are written for (Git's), so the
/// tools walk it the same way. ⚠️Not through the shell (`runInShell`): cmd
/// walks PATH itself there, and cuts this path at its space.
///
/// ⚠️A BARE `bash` STARTS WSL ON THE MAIN PC TOO (2026-11-23, 관제 →
/// 보드/인프라: WSL was turned on, by the user's leave, for the emulator).
/// Its app alias `%LOCALAPPDATA%\Microsoft\WindowsApps\bash.exe` answers
/// Windows' own lookup — PowerShell's `where.exe bash` named it first. Dart
/// takes the alias for a link, not a file, so the walk passes it by; what
/// reached it was the walk's last answer, a bare `bash`, on a PATH such as
/// PowerShell's, where no folder of Git's holds a bash (`Git\cmd` holds git
/// alone — measured that day: that PATH answered `bash`). Such a PATH still
/// names Git's git, so the bash is that install's `bin\bash.exe`, the one
/// Git's own shortcut starts.
String get bashExecutable => Platform.isWindows
    ? bashOnPath(
        (Platform.environment['PATH'] ?? '').split(';'),
        windowsFolder: Platform.environment['SystemRoot'] ?? r'C:\Windows',
        exists: (path) => File(path).existsSync(),
      )
    : 'bash';

/// The first `bash.exe` in the folders of [path] that is not under
/// [windowsFolder]; else the `bin\bash.exe` of the Git install whose
/// `git.exe` [path] names first; else `bash`.
String bashOnPath(
  List<String> path, {
  required String windowsFolder,
  required bool Function(String path) exists,
}) {
  final windows = windowsFolder.toLowerCase();
  final folders = path
      .map((e) => e.endsWith(r'\') ? e.substring(0, e.length - 1) : e)
      .where((folder) => folder.isNotEmpty)
      .toList();
  for (final folder in folders) {
    final lower = folder.toLowerCase();
    if (lower == windows || lower.startsWith('$windows\\')) continue;
    final bash = '$folder\\bash.exe';
    if (exists(bash)) return bash;
  }
  for (final folder in folders) {
    if (!exists('$folder\\git.exe')) continue;
    final root = _gitInstallOf(folder);
    if (root == null) continue;
    final bash = '$root\\bin\\bash.exe';
    if (exists(bash)) return bash;
  }
  return 'bash';
}

/// The Git install a folder holding `git.exe` belongs to: Git for Windows
/// keeps it in `cmd`, `bin` and `mingw64\bin`.
String? _gitInstallOf(String folder) {
  final lower = folder.toLowerCase();
  for (final under in [r'\mingw64\bin', r'\cmd', r'\bin']) {
    if (lower.endsWith(under)) {
      return folder.substring(0, folder.length - under.length);
    }
  }
  return null;
}
