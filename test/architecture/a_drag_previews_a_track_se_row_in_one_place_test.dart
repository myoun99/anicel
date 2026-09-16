import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WHAT A DRAG PUBLISHES FOR A TRACK-SE ROW — DECIDED IN ONE PLACE.
///
/// A track-owned SE row lives on its track's global frames and the open cut
/// shows a cut-local projection of it, so every drag that previews such a
/// row publishes TWO forms: the display clone, for the panels drawing the
/// cut, and the row itself, for the storyboard's track-global strips. Six
/// drag steps wrote that pair out by hand, each spelling
/// `trackSeWindow.displayLayer(...)` beside a global-keyed entry — and the
/// two arms that never spelled it (the lane move's transform and effects)
/// published the GLOBAL row into the cut's channel instead, which puts
/// every diamond of a moving SE row a cut's start to the right.
///
/// ⛔This scans SOURCE on purpose, like
/// `the_row_axis_offset_is_asked_in_one_place_test`: copies that agree
/// today pass every behavioural test, and copies that agree today are the
/// state this exists to end.
void main() {
  test('a row is windowed for a preview in ONE place — every drag asks '
      '`previewFormsOf`', () {
    // Where a row may still be windowed, and why none of them is a drag's
    // preview: the conversion's own home, the display clones the rails
    // render (and the preview forms, which live beside them), the read a
    // range selection resolves through, and the cut-scoped sheet export.
    const allowed = {
      'lib/src/models/track_se_window.dart',
      'lib/src/models/sheet_sources.dart',
      'lib/src/ui/session/track_se_display.dart',
      'lib/src/ui/editor_session_manager.dart',
    };
    final sites = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (allowed.contains(path)) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (lines[i].contains('displayLayer(')) {
          sites.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      sites,
      isEmpty,
      reason:
          'A row is windowed outside the place that answers what a preview '
          'publishes. Ask `TrackSeDisplay.previewFormsOf(row)` for the pair '
          'instead — half of it written by hand is how the global row '
          "reached the cut's channel and every diamond jumped by the cut's "
          'start.\n${sites.join('\n')}',
    );
  });
}
