import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import 'package:anicel/src/ui/sheet_painting.dart';
import '../../helpers/pdf_content.dart';

/// No ink on the paper prints where a picture over it shows its cut's
/// canvas (F-216). The ink keeps its piece of a stroke a ring past the
/// picture's edge (`sheetInkApron`) — the screen never shows it there, and
/// neither may the PDF: each picture's exact outline is cut out of the
/// ink's window, even-odd.
void main() {
  testWidgets('a cell\'s ink is cut by the outline of the picture over it, '
      'exactly where that shows its canvas', (tester) async {
    final source = ConteSheetSource(
      cuts: [
        ConteCutSource(
          cutId: const CutId('a'),
          name: '1',
          durationFrames: 24,
          cumulativeEndFrames: 24,
          cells: const [
            ConteCellSource(
              startFrame: 0,
              endFrameExclusive: 24,
              pictureFrame: 0,
              frameId: FrameId('f'),
              inkId: 'i',
            ),
          ],
        ),
      ],
    );
    final page = layoutConteSheet(source).single;
    final m = page.metrics;
    final width = (m.bodyWidth * conteInkScale).ceil();
    final height = (m.bodyHeight * conteInkScale).ceil();
    final ink = ContePdfPicture(
      rgba: Uint8List(width * height * 4),
      width: width,
      height: height,
    );
    // A canvas turned under the camera: its sides cut across the slot's
    // corners, an outline nothing else on the page draws.
    final slot = m.windowRect(0);
    final centre = slot.center;
    final across = slot.width * 0.8;
    final down = slot.height * 0.8;
    final over = (
      picture: SheetPicture(
        SheetPaintLayer.content,
        cutId: 'a',
        pictureFrame: 0,
        slot: slot,
        frame: slot,
      ),
      canvas: [
        centre + Offset(0, -down),
        centre + Offset(across, 0),
        centre + Offset(0, down),
        centre + Offset(-across, 0),
      ],
      // The PDF cuts by the outline alone; nothing lays a print by this.
      canvasToPaper: Matrix4.identity(),
    );
    Future<Uint8List?> written({required bool picture}) => tester.runAsync(
      () async => writeContePdf(
        source: source,
        pages: [page],
        fonts: await ContePdfFonts.load(),
        words: conteWordsIn(AppLanguage.ja),
        inkPictures: {conteInkRowKey(const CutId('a'), 'i'): ink},
        picturesOverInkOf: picture ? (_) => [over] : null,
      ),
    );

    expect(
      pdfClosedPaths((await written(picture: false))!, then: 'W*'),
      isEmpty,
      reason: 'with no picture over it, nothing cuts the ink even-odd',
    );
    final outline = pictureOutline(over);
    expect(outline.length, greaterThan(4), reason: 'the canvas cuts corners');
    final cut = pdfClosedPaths((await written(picture: true))!, then: 'W*');
    expect(cut, hasLength(1), reason: 'the one picture over the ink');
    expect(cut.single, hasLength(outline.length));
    for (final (index, point) in outline.indexed) {
      // PDF y runs up.
      expect(cut.single[index].dx, closeTo(point.dx, 0.01));
      expect(cut.single[index].dy, closeTo(m.pageHeight - point.dy, 0.01));
    }
  });
}
