import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import '../../helpers/pdf_content.dart';

/// The PDF sets each line where its mark says, by the one placement the
/// screen sets it by ([SheetAlign.place]) — centred numbers centred (유저
/// 2026-09-25: 「컷 번호 … 중앙정렬하자. 컷 길이도 … 동일하게 좌우
/// 중앙정렬」), a length at the foot of its slot.
void main() {
  ConteSheetSource oneCut(String name) => ConteSheetSource(
    cuts: [
      ConteCutSource(
        cutId: const CutId('a'),
        name: name,
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

  Future<Uint8List> pdfOf(WidgetTester tester, ConteSheetSource source) async {
    final page = layoutConteSheet(source).single;
    return (await tester.runAsync(
      () async => writeContePdf(
        source: source,
        pages: [page],
        fonts: await ContePdfFonts.load(),
        words: conteWordsIn(AppLanguage.ja),
      ),
    ))!;
  }

  /// The one text origin inside [paper] — a rect on the page, turned into
  /// the PDF's upward y.
  Offset originIn(Uint8List pdf, Rect paper, double pageHeight) =>
      pdfTextOrigins(pdf).singleWhere(
        (origin) =>
            origin.dx >= paper.left &&
            origin.dx <= paper.right &&
            origin.dy >= pageHeight - paper.bottom &&
            origin.dy <= pageHeight - paper.top,
      );

  testWidgets('a longer cut number starts further left: centred in its '
      'column, not hung from the column\'s left', (tester) async {
    final page = layoutConteSheet(oneCut('1')).single;
    final m = page.metrics;
    final column = page.cutBands.single.cutRect;
    final one = originIn(
      await pdfOf(tester, oneCut('1')),
      column,
      m.pageHeight,
    );
    final three = originIn(
      await pdfOf(tester, oneCut('111')),
      column,
      m.pageHeight,
    );
    expect(three.dx, lessThan(one.dx - 1));
    expect(three.dy, one.dy, reason: 'on one baseline');
  });

  testWidgets('the cut\'s length stands at the FOOT of its time slot', (
    tester,
  ) async {
    final source = oneCut('1');
    final page = layoutConteSheet(source).single;
    final m = page.metrics;
    final slot = Rect.fromLTRB(
      m.timeLeft,
      m.rowTop(0),
      m.bodyRight,
      m.rowTop(1),
    ).deflate(m.timeInset);
    final length = originIn(await pdfOf(tester, source), slot, m.pageHeight);
    // The baseline is a line's height at most above the slot's foot.
    expect(length.dy - (m.pageHeight - slot.bottom), inInclusiveRange(0, 12));
  });
}
