import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A CARRY IN A TEST IS A WHOLE NAME (10-08).
///
/// A carry's bytes are kept under its name, and every name is minted whole
/// (`mintMediaCarry` — the path's hash, a token, the file's own name). A bare
/// token was a carry from before that, and once those projects were refused
/// by their format number (card `old-project-shapes-are-not-read`) the name
/// rule stopped spelling one out: the staging room keeps no bytes under it
/// (`isOneStoredName`). The tests still building carries on bare tokens then
/// measured assets that were never staged — four framed-movie pins skipped
/// for an evening that way, their skip saying there was no engine.
///
/// Build one with `wholeCarry` (`test/helpers/whole_carry.dart`) or name it
/// with `mediaCarryNamed`.
void main() {
  test('no test builds a carry on a bare token', () {
    final bare = RegExp(
      r"(?:carriedAs:\s*|poolPath:[^,()]*,\s*token:\s*)'([A-Za-z0-9_]*)'",
    );
    final carries = RegExp('carriedAs:|poolPath:');
    var seen = 0;
    final found = <String>[];
    for (final file in dartFilesUnder('test')) {
      final text = file.readAsStringSync();
      seen += carries.allMatches(text).length;
      for (final match in bare.allMatches(text)) {
        found.add('${file.path.replaceAll(r'\', '/')}: ${match[0]}');
      }
    }

    expect(seen, greaterThan(20), reason: '⛔전제: the tests build carries');
    expect(
      found,
      isEmpty,
      reason:
          'a bare token is a carry no project can hold, and nothing is '
          'staged under it — build it with wholeCarry or mediaCarryNamed',
    );
  });
}
