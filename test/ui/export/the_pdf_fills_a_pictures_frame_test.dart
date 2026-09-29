import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import '../../helpers/pdf_content.dart';

/// The PDF lays a cell's picture over the camera's frame in its window —
/// the rect the page's marks name, the one the panel and the pen read —
/// not a rect worked out from the picture's pixels (F-197). A picture
/// rendered some pixels wide is the camera's shape only to the nearest
/// pixel, and contained by those pixels it left a sliver of the window
/// bare.
void main() {
  testWidgets('a picture a pixel off the camera\'s shape still fills its '
      'window\'s frame', (tester) async {
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
            ),
          ],
        ),
      ],
    );
    final page = layoutConteSheet(source).single;
    final m = page.metrics;
    // 64×35 against the camera's 16:9 (64×36).
    final picture = ContePdfPicture(rgba: _black, width: 64, height: 35);
    final pdf = await tester.runAsync(
      () async => writeContePdf(
        source: source,
        pages: [page],
        fonts: await ContePdfFonts.load(),
        words: conteWordsIn(AppLanguage.ja),
        pictures: {
          (cutId: 'a', pictureFrame: 0, canvasRegion: null): picture,
        },
      ),
    );

    final frame = contePictureOf(page.cells.single, m).frame;
    // The PDF's y runs up the page.
    final expected = Rect.fromLTRB(
      frame.left,
      m.pageHeight - frame.bottom,
      frame.right,
      m.pageHeight - frame.top,
    );
    final laid = pdfImagePlacements(pdf!);
    expect(laid, hasLength(1), reason: 'fixture: one picture, no logo');
    for (final (actual, wanted) in [
      (laid.single.left, expected.left),
      (laid.single.top, expected.top),
      (laid.single.right, expected.right),
      (laid.single.bottom, expected.bottom),
    ]) {
      expect(actual, closeTo(wanted, 0.01));
    }
  });
}

final Uint8List _black = Uint8List.fromList([
  for (var i = 0; i < 64 * 35; i += 1) ...[0, 0, 0, 255],
]);
