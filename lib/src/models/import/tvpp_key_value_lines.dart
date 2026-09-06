/// The `key=value` lines of a clip-config INI section as a map — the
/// `[cameradata]` block, and each `[audio+N]` section.
///
/// ⛔TWO READERS PARSED IT. The profile baker wants the mpoint channels
/// and the clip parser wants the camera points, and both start from the
/// same flat map — an `=` at index 0 is not a key, and everything after
/// the FIRST `=` is the value (a value may contain one). The audio-track
/// reader was the third, with its own copy of the same loop; a section
/// header line (`[audio+0]`) carries no `=` and so drops out like any
/// other keyless line.
///
/// ⚠️A LEAF FILE, on purpose: the baker and the parser already import each
/// other's neighbourhood, and putting the shared piece in either of them
/// closed an import loop (`no_import_cycles_test` said so, and said to do
/// exactly this).
library;

Map<String, String> tvppKeyValueLines(String text) {
  final values = <String, String>{};
  for (final line in text.split('\n')) {
    final eq = line.indexOf('=');
    if (eq > 0) {
      values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }
  }
  return values;
}
