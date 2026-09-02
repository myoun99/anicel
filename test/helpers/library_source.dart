import 'dart:io';

/// The source of a Dart LIBRARY — the file plus every `part` it declares —
/// for the tests that read code rather than run it.
///
/// The audit's SRP cuts (2026-09-02) carve the big State and service classes
/// into collaborator parts beside them, so a scan that names one file misses
/// the code a cut moved and either goes quietly empty (「빈 것을 쟀다」) or
/// flags a caller that merely changed file. Reading the library — exactly the
/// parts the file itself lists — follows every cut with no directory
/// convention to keep in step.
String librarySource(String path) {
  final file = File(path);
  final source = file.readAsStringSync();
  final directory = file.parent.path;
  return [
    source,
    for (final match in RegExp(
      r"^part\s+'([^']+)';",
      multiLine: true,
    ).allMatches(source))
      File('$directory/${match.group(1)}').readAsStringSync(),
  ].join('\n');
}
