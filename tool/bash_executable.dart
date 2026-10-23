import 'dart:io';

/// The bash a tool starts: on Windows, the first `bash.exe` on PATH outside
/// the Windows folder; elsewhere, or when PATH holds none, `bash`.
///
/// ⚠️Windows starts a bare `bash` from its own folder before it looks at
/// PATH, and `System32\bash.exe` there is WSL's launcher, not a shell: with
/// no Linux distribution installed it only fails. GitHub's Windows runners
/// carry it — 2026-10-24 `parityTests` answered null on the runner and green
/// on the main PC, which has no launcher. A shell asked for `bash` walks
/// PATH, and that is the bash the scripts are written for (Git's), so the
/// tools walk it the same way. ⚠️Not through the shell (`runInShell`): cmd
/// walks PATH itself there, and cuts this path at its space.
String get bashExecutable => Platform.isWindows
    ? bashOnPath(
        (Platform.environment['PATH'] ?? '').split(';'),
        windowsFolder: Platform.environment['SystemRoot'] ?? r'C:\Windows',
        exists: (path) => File(path).existsSync(),
      )
    : 'bash';

/// The first `bash.exe` in the folders of [path] that is not under
/// [windowsFolder], or `bash` when there is none.
String bashOnPath(
  List<String> path, {
  required String windowsFolder,
  required bool Function(String path) exists,
}) {
  final windows = windowsFolder.toLowerCase();
  for (final entry in path) {
    final folder = entry.endsWith(r'\')
        ? entry.substring(0, entry.length - 1)
        : entry;
    final lower = folder.toLowerCase();
    if (folder.isEmpty || lower == windows || lower.startsWith('$windows\\')) {
      continue;
    }
    final bash = '$folder\\bash.exe';
    if (exists(bash)) return bash;
  }
  return 'bash';
}
