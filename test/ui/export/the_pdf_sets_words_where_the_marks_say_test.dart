import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:pdf/pdf.dart' show TtfParser;
import '../../helpers/pdf_content.dart';

/// The PDF sets each line where its mark says, by the one placement the
/// screen sets it by ([SheetAlign.place]) — centred numbers centred (유저
/// 2026-09-25: 「컷 번호 … 중앙정렬하자. 컷 길이도 … 동일하게 좌우
/// 중앙정렬」), a length at the foot of its slot.
void main() {
  ConteSheetSource oneCut(String name, {String action = ''}) =>
      ConteSheetSource(
        cuts: [
          ConteCutSource(
            cutId: const CutId('a'),
            name: name,
            durationFrames: 24,
            cumulativeEndFrames: 24,
            cells: [
              ConteCellSource(
                startFrame: 0,
                endFrameExclusive: 24,
                pictureFrame: 0,
                action: action,
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

  group('connection-round-checklist-Q22 (유저 2026-11-08): 「콘티도 끝에 Noto Sans '
      'SC 를 더한다」', () {
    // Simplified: the Japanese and the Korean face do not have it.
    const chineseOnly = '这';

    bool has(({String regular, String bold}) files, String letter) => TtfParser(
      ByteData.sublistView(File(files.regular).readAsBytesSync()),
    ).charToGlyphIndexMap.containsKey(letter.runes.single);

    Future<Set<String>> facesOf(
      WidgetTester tester, {
      required String name,
      String action = '',
    }) async => pdfFontsSetIn(await pdfOf(tester, oneCut(name, action: action)));

    test('the letter is one only the last face has', () {
      expect(has(AppTypography.bundledFiles, chineseOnly), isFalse);
      expect(has(AppTypography.bundledFallbackFiles, chineseOnly), isFalse);
      expect(has(AppTypography.chineseFiles, chineseOnly), isTrue);
    });

    testWidgets('a letter neither face has is set in it, at the bold word\'s '
        'weight', (tester) async {
      expect(
        await facesOf(tester, name: chineseOnly),
        allOf(contains('NotoSansSC-Bold'), isNot(contains('NotoSansSC-Regular'))),
      );
    });

    testWidgets('a letter neither face has is set in it, at the plain word\'s '
        'weight', (tester) async {
      expect(
        await facesOf(tester, name: '1', action: chineseOnly),
        allOf(contains('NotoSansSC-Regular'), isNot(contains('NotoSansSC-Bold'))),
      );
    });

    testWidgets('it stands BEHIND the other two: a kanji is the first face\'s, '
        'Hangul and the keyboard\'s `~`, which it has too, the second\'s', (
      tester,
    ) async {
      final faces = await facesOf(tester, name: '漢한~', action: '漢한~');
      expect(faces, containsAll(['NanumGothicBold', 'NanumGothic']));
      expect(faces.where((face) => face.startsWith('NotoSansSC')), isEmpty);
    });
  });
}
