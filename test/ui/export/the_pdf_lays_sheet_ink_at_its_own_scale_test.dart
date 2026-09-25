import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import '../../helpers/pdf_content.dart';

/// Sheet ink prints in the PDF the way the page shows it: its raster laid
/// at the ink's own scale from its window's corner, and clipped to the
/// window — the screen's `paintSheetInkWindow`, in PDF space.
///
/// A cell's ink surface is the whole BODY's (a cell that grows over more
/// rows reveals more of the same surface), and its band shows the top of
/// it. Stretched whole into the band, the handwriting came out squeezed —
/// five times over for a one-row cell — on paper only.
void main() {
  testWidgets('a cell\'s ink is laid at the ink\'s scale from its band\'s '
      'corner — not squeezed into the band', (tester) async {
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
            ),
          ],
        ),
      ],
    );
    final page = layoutConteSheet(source).single;
    final m = page.metrics;
    const scale = conteInkScale;
    // The row plane's surface: the body, at the ink's scale.
    final width = (m.bodyWidth * scale).ceil();
    final height = (m.bodyHeight * scale).ceil();
    final ink = ContePdfPicture(
      rgba: Uint8List(width * height * 4),
      width: width,
      height: height,
    );
    final pdf = await tester.runAsync(
      () async => writeContePdf(
        source: source,
        pages: [page],
        fonts: await ContePdfFonts.load(),
        words: conteWordsIn(AppLanguage.ja),
        inkPictures: {
          conteInkRowKey(const CutId('a'), const FrameId('f')): ink,
        },
      ),
    );

    final band = page.cells.single.rowBandRect(m);
    final laid = pdfImagePlacements(
      pdf!,
    ).singleWhere((placed) => (placed.left - band.left).abs() < 0.01);
    expect(
      laid.height,
      closeTo(height / scale, 0.01),
      reason: 'the body\'s height of ink, the band showing the top of it',
    );
    expect(laid.width, closeTo(width / scale, 0.01));
    // PDF y runs up: its top edge is the band's top.
    expect(laid.top + laid.height, closeTo(m.pageHeight - band.top, 0.01));
  });
}
