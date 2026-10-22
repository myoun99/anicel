import 'dart:io';

/// Every `.dart` file under [dir], at any depth — for the tests that scan
/// source rather than run it.
///
/// 🚨ONE WALK (C-save-percent, 2026-09-15). Seven ratchets in
/// `test/architecture/` each carried this walk and [libPath] as private
/// copies, and an eighth was about to be pasted. Two of the seven skipped a
/// folder that did not exist; the walk FAILS on one instead — a scan whose
/// folder was renamed must go red, not quietly measure nothing (「빈 것을
/// 쟀다」).
Iterable<File> dartFilesUnder(String dir) =>
    filesUnder(dir).where((file) => file.path.endsWith('.dart'));

/// Every file under [dir], at any depth and of any kind — for a scan of
/// what the scripts and workflows say, where the Dart filter sees nothing.
/// The one walk [dartFilesUnder] filters, so it fails on a missing folder
/// too.
Iterable<File> filesUnder(String dir) sync* {
  for (final entity in Directory(dir).listSync(recursive: true)) {
    if (entity is File) yield entity;
  }
}

/// [file]'s path from `lib/` on, with forward slashes — how a scan names
/// what it found.
String libPath(File file) {
  final path = file.path.replaceAll(r'\', '/');
  return path.substring(path.indexOf('lib/'));
}
