import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ledger.dart';

/// 🚨WHAT A CEL IS KEPT AS STOPS BEING ITS CEL'S THROUGH ONE DOOR
/// (`BrushFrameStore._holdOn`, card
/// `cel-originals-are-held-twice-in-ram-and-on-the-gpu`; 🗣️유저 2026-11-21
/// on Q4, 「최대한 사본안만드는게 중요」). The tiles of a cel's shells hold no
/// bytes and read what the cel is kept as, so what it is kept as is held on
/// for them before it goes (`BrushFrameStore._heldOn`). A ref taken out of
/// its map past the door leaves such a tile reading another picture — and
/// no run shows it till a pool is full and the tile's slot has gone.
///
/// ⛔A source ratchet beside the behaviour pins
/// (`an_edited_cel_reads_what_it_was_kept_as_test.dart`): a pass over the
/// kept cels took a cel's ref out of its map itself till 2026-11-21
/// (`_rewriteKeptCels` — a canvas resized, a pasteboard's wall moved), and
/// every pin of the door passed beside it.
void main() {
  /// A line's code, its `//` comment apart.
  String code(String line) {
    final comment = line.indexOf('//');
    return comment < 0 ? line : line.substring(0, comment);
  }

  test('🚨a kept ref leaves its map at the door, at a rename and where a '
      'park is dropped — and nowhere else', () {
    final source = File(
      'lib/src/services/brush_frame_store.dart',
    ).readAsLinesSync();
    final taken = [
      for (final line in source.map(code))
        if (line.contains('_fileCels.remove(') ||
            line.contains('_coldCels.remove('))
          line.trim(),
    ];
    expectSetMatchesLedger(
      taken,
      const [
        // The door (`_letTheFileRefGo`): held on first (`_holdOn`).
        'return _fileCels.remove(key);',
        // A rename (`_keptMoves`): kept where it was, and its tiles read
        // by the name it has from there.
        'final parked = _coldCels.remove(from);',
        'final inTheFile = _fileCels.remove(from);',
        // A park dropped (`_dropCold`): behind the door (`_letTheKeptGo`),
        // or where a save keeps the same bytes in its file
        // (`adoptSavedFile`).
        'final gone = _coldCels.remove(key);',
      ],
      unledgered:
          'A cel\'s kept ref is taken out of its map here, past the door: '
          'the tiles that wait in what it was kept as are not held on for. '
          'Go through `_letTheFileRefGo` (a stretch of the saved file) or '
          '`_letTheKeptGo` (its park too) — or `_holdOn` first, where the '
          'park is replaced beside it.',
      paidOff:
          'These lines are gone from the store — take them off the list '
          'here.',
    );
  });
}
