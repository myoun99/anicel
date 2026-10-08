import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_body.dart';

/// 🚨★★★**A HELD PICTURE LANDS THROUGH ONE DOOR** (F-293).
///
/// 🗣️유저 2026-10-05: 「잘라내기도구의 스탬프, 여러 프레임 선택해서 여러프레임
/// 붙여넣을수있도록. **색편집의 픽셀붙여넣기랑 법 통일**」.
///
/// 픽셀 위 / 아래 붙여넣기 and the cut tool's stamp — the press, the drag's
/// trail, 원래 위치에 붙여넣기 — are one verb: a held picture laid on the cels
/// a press names. `pieceLandings` (`services/piece_landing.dart`) is where
/// it is written.
///
/// ⛔A source ratchet beside the behaviour pins
/// (`the_stamp_lands_where_the_pixel_paste_lands_test`), because two doors
/// can agree wherever a pin happens to look: the stamp went down the pen's
/// funnel beside a paste that landed on a whole range (I-55, 2026-10-01),
/// and no pin compared the two.
void main() {
  /// A line's code, its `//` comment apart — a comment may name the door
  /// all it likes.
  String code(String line) {
    final comment = line.indexOf('//');
    return comment < 0 ? line : line.substring(0, comment);
  }

  /// The files under `lib/src` whose code spells [call], and how many were
  /// read to find them.
  ({List<String> files, int scanned}) spelling(String call) {
    final files = <String>[];
    var scanned = 0;
    for (final file in dartFilesUnder('lib/src')) {
      scanned += 1;
      if (file.readAsLinesSync().map(code).any((l) => l.contains(call))) {
        files.add(libPath(file));
      }
    }
    return (files: files..sort(), scanned: scanned);
  }

  test('🚨a piece is cut through a selection\'s soft mask in the door, and '
      'nowhere else', () {
    final found = spelling('clipStampDabToSelectionMask(');
    expect(found.scanned, greaterThan(500), reason: 'the scan found lib/src');
    expect(found.files, [
      // Where it is declared.
      'lib/src/services/canvas_selection_paint_clip.dart',
      'lib/src/services/piece_landing.dart',
    ]);
  });

  test('🚨a piece\'s dab is built by the roads that hand it to the door', () {
    expect(spelling('buildCutStampDab(').files, [
      'lib/src/services/cut_piece_stamp.dart',
      'lib/src/ui/brush/canvas_panel/canvas_panel_tap.dart',
    ]);
    expect(spelling('buildCutPasteDab(').files, [
      'lib/src/services/cut_piece_stamp.dart',
      'lib/src/ui/brush/brush_canvas_panel.dart',
      // ⛔Not a road onto CELS: a picture dropped on the envelope lands on
      // the sheet's ink, through the window it was dropped on — the pen's
      // funnel there, which has no ladder and no cel to name. It borrows
      // the builder for 「this picture, with its corner here」.
      'lib/src/ui/envelope/envelope_picture_drop.dart',
      'lib/src/ui/session/pixel_verbs.dart',
    ]);
  });

  test('⛔no road a stamp takes goes down the pen\'s funnel', () {
    final tap = File(
      'lib/src/ui/brush/canvas_panel/canvas_panel_tap.dart',
    ).readAsLinesSync().map(code).join('\n');
    expect(
      tap.contains('_commitSourceStroke('),
      isFalse,
      reason: 'the press and the trail land through `_landStamp`',
    );
    expect(tap.contains('_landStamp('), isTrue, reason: 'premise');

    final panel = File(
      'lib/src/ui/brush/brush_canvas_panel.dart',
    ).readAsStringSync();
    final pasteInPlace = sourceBodyOf(panel, 'void pasteCutPieceAtOrigin()');
    expect(pasteInPlace.contains('_landStamp('), isTrue);
    expect(pasteInPlace.contains('_commitSourceStroke('), isFalse);
    final landStamp = sourceBodyOf(panel, 'void _landStamp(');
    expect(landStamp.contains('pieceLandings('), isTrue);
    expect(landStamp.contains('_commitSourceStroke('), isFalse);

    final verbs = File(
      'lib/src/ui/session/pixel_verbs.dart',
    ).readAsStringSync();
    expect(
      sourceBodyOf(verbs, 'void _pastePixels(').contains('pieceLandings('),
      isTrue,
      reason: 'and the paste lands through the same one',
    );
  });
}
