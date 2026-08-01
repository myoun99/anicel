import 'dart:ui' as ui;

import 'package:anicel/src/ui/text/vertical_writing.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Canvas] that records which verbs the vertical renderer used. The
/// rotation contract is invisible to a widget finder — the glyph is drawn,
/// just lying down — so the test has to watch the canvas.
class _SpyCanvas implements Canvas {
  final List<Symbol> calls = <Symbol>[];
  final List<double> rotations = <double>[];
  final List<Offset> translations = <Offset>[];

  @override
  void rotate(double radians) {
    calls.add(#rotate);
    rotations.add(radians);
  }

  @override
  void translate(double dx, double dy) {
    calls.add(#translate);
    translations.add(Offset(dx, dy));
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    calls.add(#drawParagraph);
  }

  @override
  void save() => calls.add(#save);

  @override
  void restore() => calls.add(#restore);

  @override
  void scale(double sx, [double? sy]) => calls.add(#scale);

  @override
  int getSaveCount() => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    return null;
  }

  int get glyphCount => calls.where((c) => c == #drawParagraph).length;
}

void main() {
  group('vertical glyph forms', () {
    test('the long-vowel and dash family rotates', () {
      for (final char in ['ー', 'ｰ', '－', '〜', '～', '—', '–', '~', '-', '＿']) {
        expect(
          verticalGlyphForm(char),
          VerticalGlyphForm.rotated,
          reason: '$char must lie along the column',
        );
      }
    });

    test('every bracket family rotates', () {
      // The user's real cut folders carry process names like [연출].
      for (final char in [
        '（', '）', '(', ')',
        '［', '］', '[', ']',
        '「', '」', '『', '』',
        '【', '】', '〔', '〕',
        '｛', '｝', '{', '}',
        '〈', '〉', '《', '》',
        '＜', '＞', '<', '>',
      ]) {
        expect(
          verticalGlyphForm(char),
          VerticalGlyphForm.rotated,
          reason: '$char must rotate',
        );
      }
    });

    test('ellipses, equals and colons rotate', () {
      for (final char in ['…', '‥', '⋯', '＝', '=', '：', '；', '‖', '∥']) {
        expect(verticalGlyphForm(char), VerticalGlyphForm.rotated);
      }
    });

    test('full-width punctuation swaps corners, small kana only lean', () {
      for (final char in ['、', '。', '，', '．']) {
        expect(verticalGlyphForm(char), VerticalGlyphForm.shifted);
        expect(verticalGlyphShiftEm(char), verticalCornerShiftEm);
      }
      for (final char in ['ゃ', 'っ', 'ぁ', 'ャ', 'ッ', 'ヶ', '゛']) {
        expect(verticalGlyphForm(char), VerticalGlyphForm.shifted);
        expect(verticalGlyphShiftEm(char), verticalSmallKanaShiftEm);
      }
    });

    test('kanji, kana, repetition marks and roman letters stand upright', () {
      for (final char in ['亜', 'あ', 'ア', '々', '〆', '〇', 'A', 'カ']) {
        expect(verticalGlyphForm(char), VerticalGlyphForm.upright);
        expect(verticalGlyphShiftEm(char), 0);
      }
    });
  });

  group('cell segmentation', () {
    test('A12 costs TWO cells, not three (縦中横)', () {
      // This is the whole point: stacking A/1/2 shrinks a cel name to 7px,
      // and pairing the digits is how a paper timesheet writes it anyway.
      expect(verticalTextCells('A12'), const [
        VerticalTextCell(text: 'A', form: VerticalGlyphForm.upright),
        VerticalTextCell(text: '12', form: VerticalGlyphForm.tateChuYoko),
      ]);
    });

    test('a lone digit stays upright', () {
      expect(verticalTextCells('A1'), const [
        VerticalTextCell(text: 'A', form: VerticalGlyphForm.upright),
        VerticalTextCell(text: '1', form: VerticalGlyphForm.upright),
      ]);
    });

    test('a run longer than the rule stays upright, never cut in half', () {
      expect(
        verticalTextCells('A123').map((c) => c.text).toList(),
        ['A', '1', '2', '3'],
      );
      expect(
        verticalTextCells('A123').every(
          (c) => c.form == VerticalGlyphForm.upright,
        ),
        isTrue,
      );
    });

    test('full-width digits pair too', () {
      expect(verticalTextCells('２４'), const [
        VerticalTextCell(text: '２４', form: VerticalGlyphForm.tateChuYoko),
      ]);
    });

    test('a bracketed process name rotates its brackets', () {
      final cells = verticalTextCells('[연출]');
      expect(cells.length, 4);
      expect(cells.first.form, VerticalGlyphForm.rotated);
      expect(cells.last.form, VerticalGlyphForm.rotated);
      expect(cells[1].form, VerticalGlyphForm.upright);
    });

    test('empty text yields no cells', () {
      expect(verticalTextCells(''), isEmpty);
    });
  });

  group('fit', () {
    // The timesheet's OWN numbers, read from the painter rather than
    // invented: rows of [TimesheetDocumentLayout.rowHeight], glyphs up to
    // 10px with 3px of leading. The shared function must reproduce them
    // exactly, or the printed sheet moves the day this lands.
    const rowHeight = TimesheetDocumentLayout.rowHeight;

    VerticalTextFit fitFor(int cells, int rows) => verticalTextFit(
      cellCount: cells,
      mainExtent: rows * rowHeight,
      naturalCellExtent: rowHeight,
      maxFontSize: 10,
    );

    test('room to spare: cells keep their natural extent', () {
      final fit = fitFor(3, 5);
      expect(fit.cellExtent, rowHeight);
      expect(fit.fontSize, 10);
      expect(fit.totalExtent, 3 * rowHeight);
    });

    test('cramped: cells pack evenly and the glyphs shrink with them', () {
      final fit = fitFor(6, 3);
      expect(fit.cellExtent, closeTo(9, 1e-9));
      expect(fit.fontSize, closeTo(6, 1e-9));
      expect(fit.totalExtent, closeTo(3 * rowHeight, 1e-9));
    });

    test('the floor holds — packing never shrinks a glyph out of existence', () {
      expect(fitFor(12, 1).fontSize, 4);
      expect(fitFor(40, 1).fontSize, 4);
    });

    test('no cells, no extent', () {
      expect(fitFor(0, 5).totalExtent, 0);
    });
  });

  group('renderer', () {
    test('paints one glyph per CELL and rotates only what must rotate', () {
      final canvas = _SpyCanvas();
      // リピート: four characters, one of them the long-vowel bar.
      paintVerticalText(
        canvas,
        'リピート',
        style: const TextStyle(fontSize: 10, color: Color(0xFF000000)),
        centerX: 10,
        top: 0,
        mainExtent: 52,
        naturalCellExtent: 13,
      );
      expect(canvas.glyphCount, 4);
      expect(canvas.rotations.length, 1);
      expect(canvas.rotations.single, closeTo(3.14159265 / 2, 1e-5));
    });

    test('a two-digit run draws ONE paragraph, not two', () {
      final canvas = _SpyCanvas();
      paintVerticalText(
        canvas,
        'A12',
        style: const TextStyle(fontSize: 10, color: Color(0xFF000000)),
        centerX: 10,
        top: 0,
        mainExtent: 52,
        naturalCellExtent: 13,
      );
      expect(canvas.glyphCount, 2);
      expect(canvas.rotations, isEmpty);
    });

    test('a shifted glyph moves right and up by half its em', () {
      final canvas = _SpyCanvas();
      paintVerticalText(
        canvas,
        '。',
        style: const TextStyle(fontSize: 10, color: Color(0xFF000000)),
        centerX: 10,
        top: 0,
        mainExtent: 13,
        naturalCellExtent: 13,
      );
      // fontSize is min(10, 13 - 3) = 10, so the shift is 5px each way from
      // the cell centre (10, 6.5).
      expect(canvas.translations.single.dx, closeTo(15, 1e-9));
      expect(canvas.translations.single.dy, closeTo(1.5, 1e-9));
    });

    test('empty text paints nothing', () {
      final canvas = _SpyCanvas();
      final painted = paintVerticalText(
        canvas,
        '',
        style: const TextStyle(fontSize: 10),
        centerX: 0,
        top: 0,
        mainExtent: 50,
        naturalCellExtent: 13,
      );
      expect(painted, 0);
      expect(canvas.calls, isEmpty);
    });

    testWidgets('the widget carries the whole label as one semantics node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 36,
                height: 120,
                child: VerticalWritingText(
                  text: 'ACTION',
                  style: TextStyle(fontSize: 9),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('ACTION'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('text scaling reaches the CELLS, not just the glyphs', (
      tester,
    ) async {
      // The widget this replaced was a FittedBox and got this for free.
      // Scaling only the TextPainters would grow the letters inside cells
      // that stayed the same height, and they would overlap.
      Future<Size> sizeAt(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: VerticalWritingText(
                    text: 'ACTION',
                    style: TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.byType(VerticalWritingText));
      }

      final plain = await sizeAt(1);
      final scaled = await sizeAt(2);
      expect(scaled.height, closeTo(plain.height * 2, 0.01));
      expect(scaled.width, closeTo(plain.width * 2, 0.01));
    });

    testWidgets('an UNBOUNDED host sizes to the column instead of throwing', (
      tester,
    ) async {
      // `SectionBandZone` passes a null extent and is saved today only by
      // the Positioned around it; a scroll view is one refactor away.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerticalWritingText(
                text: 'ACTION',
                style: TextStyle(fontSize: 9),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(VerticalWritingText)).height,
        greaterThan(0),
      );
    });

    testWidgets('the widget survives a cramped host', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 36,
                height: 14,
                child: ClipRect(
                  child: VerticalWritingText(
                    text: 'リピート',
                    style: TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
