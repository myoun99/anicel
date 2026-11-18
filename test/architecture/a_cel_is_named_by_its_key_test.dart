@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨A CEL'S NAME COMES FROM ITS KEY: `BrushFrameKey.cel`.
///
/// The `(layerId, frameId)` record a canvas shows (`ShownCel`), a tile
/// picture's lineage and the engine ledger's cel are keyed by was built by
/// hand from a key in eight places — five of them the lineage a painter
/// hands its tile pictures — and the ink box's next callers would have
/// added more (2번 레인, 2026-11-08). One getter answers it; this holds the
/// next caller to it.
void main() {
  test('no file builds a cel name out of a key by hand', () {
    final byHand = <String, int>{};
    for (final root in ['lib', 'test']) {
      for (final entity in dartFilesUnder(root)) {
        final path = entity.path.replaceAll(r'\', '/');
        final found = _byHand.allMatches(entity.readAsStringSync()).length;
        if (found > 0) {
          byHand[path.substring(path.indexOf('$root/'))] = found;
        }
      }
    }
    // LIVENESS — the scan sees the one view that is handed its row and its
    // frame apart, as two fields and no key, and builds the name from them.
    expect(
      byHand.remove('lib/src/ui/canvas/interactive_brush_edit_canvas_view.dart'),
      2,
    );
    expect(
      byHand,
      isEmpty,
      reason: 'a key names its cel through BrushFrameKey.cel',
    );
  });
}

/// A record of one receiver's `layerId` and then the same receiver's
/// `frameId`.
final _byHand = RegExp(
  r'\(\s*([A-Za-z_][\w.]*)\.layerId,\s*\1\.frameId\s*\)',
);
