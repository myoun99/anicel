/// The `[cameradata]` block's `key=value` lines as a map.
///
/// ⛔TWO READERS PARSED IT. The profile baker wants the mpoint channels
/// and the clip parser wants the camera points, and both start from the
/// same flat map — an `=` at index 0 is not a key, and everything after
/// the FIRST `=` is the value (a value may contain one).
///
/// ⚠️A LEAF FILE, on purpose: the baker and the parser already import each
/// other's neighbourhood, and putting the shared piece in either of them
/// closed an import loop (`no_import_cycles_test` said so, and said to do
/// exactly this).
library;

Map<String, String> tvppCameraDataValues(String cameraDataText) {
  final values = <String, String>{};
  for (final line in cameraDataText.split('\n')) {
    final eq = line.indexOf('=');
    if (eq > 0) {
      values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }
  }
  return values;
}
