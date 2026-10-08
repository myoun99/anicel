import 'dart:ui' as ui;

import 'package:anicel/src/ui/text/vertical_writing.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';
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

  final List<(double, double)> scales = <(double, double)>[];

  @override
  void scale(double sx, [double? sy]) {
    calls.add(#scale);
    scales.add((sx, sy ?? sx));
  }

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
        '（',
        '）',
        '(',
        ')',
        '［',
        '］',
        '[',
        ']',
        '「',
        '」',
        '『',
        '』',
        '【',
        '】',
        '〔',
        '〕',
        '｛',
        '｝',
        '{',
        '}',
        '〈',
        '〉',
        '《',
        '》',
        '＜',
        '＞',
        '<',
        '>',
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
      expect(verticalTextCells('A123').map((c) => c.text).toList(), [
        'A',
        '1',
        '2',
        '3',
      ]);
      expect(
        verticalTextCells(
          'A123',
        ).every((c) => c.form == VerticalGlyphForm.upright),
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

  group('Latin turns sideways instead of stacking', () {
    test('a WORD is one turned cell, spanning several slots', () {
      final cells = verticalTextCells('Multiply');
      expect(cells, hasLength(1));
      expect(cells.single.form, VerticalGlyphForm.sideways);
      expect(cells.single.text, 'Multiply');
      // Stacked it cost EIGHT slots and fell to 5.8pt in a 28px column;
      // turned it costs about half, at full size.
      expect(cells.single.spanCells, lessThan(8));
      expect(verticalTextSpanCount(cells), cells.single.spanCells);
    });

    test('an internal space stays inside the phrase', () {
      // `Pass Through` reads as one turned line, not two words with a
      // stacked blank between them.
      final cells = verticalTextCells('Pass Through');
      expect(cells, hasLength(1));
      expect(cells.single.text, 'Pass Through');
      expect(cells.single.form, VerticalGlyphForm.sideways);
    });

    test('a trailing space is NOT swallowed into the run', () {
      final cells = verticalTextCells('Color ');
      expect(cells.first.text, 'Color');
      expect(cells.last.text, ' ');
    });

    test('a LONE letter still stands upright — A-1 reads A│1', () {
      final cells = verticalTextCells('A-1');
      expect(cells.map((c) => c.form).toList(), const [
        VerticalGlyphForm.upright,
        VerticalGlyphForm.rotated,
        VerticalGlyphForm.upright,
      ]);
    });

    test('the LATIN SCRIPT, not just ASCII — an accent stays in its word', () {
      // ASCII-only split `Café` into `Caf` sideways plus an upright `é`:
      // one word set in two orientations at once.
      for (final word in ['Café', 'Größe', 'Łódź']) {
        final cells = verticalTextCells(word);
        expect(cells, hasLength(1), reason: word);
        expect(cells.single.text, word);
        expect(cells.single.form, VerticalGlyphForm.sideways);
      }
      // Kana and Hangul are NOT Latin — they keep standing upright, which
      // is the whole point of vertical setting.
      expect(
        verticalTextCells(
          'カナ',
        ).every((c) => c.form != VerticalGlyphForm.sideways),
        isTrue,
      );
      expect(
        verticalTextCells(
          '한글',
        ).every((c) => c.form != VerticalGlyphForm.sideways),
        isTrue,
      );
    });

    test('a space carries on into a WORD, not into cel notation', () {
      // `FOLLOW PAN A2` is the phrase and then the cel — the run used to
      // swallow the `A`, leaving a stray upright `2`.
      final cells = verticalTextCells('FOLLOW PAN A2');
      expect(cells.first.text, 'FOLLOW PAN');
      expect(cells.map((c) => c.text).toList(), ['FOLLOW PAN', ' ', 'A', '2']);
      // Two real words still join.
      expect(verticalTextCells('Pass Through').single.text, 'Pass Through');
    });

    test('every character survives segmentation, whatever the input', () {
      // An index that fails to advance is an infinite loop, not a wrong
      // pixel — so the scanner is swept rather than spot-checked.
      for (final text in [
        'A',
        'A B',
        'AB CD EF',
        'Color ',
        ' Color',
        'A  B',
        '   ',
        'PAN A2 focus',
        '焼き込みカラー',
        'A-1',
        'Layer 1 - copy',
        'がぎ゙ー[연출]',
        'A12B34',
      ]) {
        final cells = verticalTextCells(text);
        expect(
          cells.map((c) => c.text).join(),
          text,
          reason: 'segmentation lost or duplicated characters in "$text"',
        );
      }
    });

    test('Japanese is untouched — it was always the legible case', () {
      final cells = verticalTextCells('焼き込みカラー');
      expect(cells.every((c) => c.form != VerticalGlyphForm.sideways), isTrue);
      expect(cells.last.form, VerticalGlyphForm.rotated);
    });
  });

  group('a column that does not fit ELLIPSISES, it does not shrink', () {
    test('everything fits: the cells come back untouched', () {
      final cells = verticalTextCells('あいう');
      expect(verticalTextCellsWithin(cells, capacityCells: 3), cells);
      expect(verticalTextCellsWithin(cells, capacityCells: 9), cells);
    });

    test('the tail is replaced by a rotated ellipsis', () {
      final cells = verticalTextCells('あいうえお');
      final kept = verticalTextCellsWithin(cells, capacityCells: 3);
      expect(kept.map((c) => c.text).toList(), ['あ', 'い', '…']);
      // Rotated, an ellipsis reads as the vertical ⋮ it should be.
      expect(kept.last.form, VerticalGlyphForm.rotated);
    });

    test('an overflowing sideways run ellipsises INSIDE itself', () {
      // The regression this pins: a whole phrase is ONE cell, so "does not
      // fit" used to throw every letter away and render a bare `…`. In the
      // default (English) UI that hit the x-sheet's layer names, eight of
      // the fourteen blend modes, and a one-row section band — and
      // Japanese never showed it, because there every glyph is its own
      // 1-span cell.
      final kept = verticalTextCellsWithin(
        verticalTextCells('Multiply'),
        capacityCells: 4,
      );
      expect(kept, hasLength(1));
      expect(kept.single.form, VerticalGlyphForm.sideways);
      expect(kept.single.text, endsWith('…'));
      expect(kept.single.text, startsWith('M'));
      expect(kept.single.spanCells, lessThanOrEqualTo(4));
    });

    test('a run that follows other cells is cut against what is LEFT', () {
      final kept = verticalTextCellsWithin(
        verticalTextCells('あMultiply'),
        capacityCells: 5,
      );
      expect(kept.first.text, 'あ');
      expect(kept.last.form, VerticalGlyphForm.sideways);
      expect(kept.last.text, endsWith('…'));
      expect(
        verticalTextSpanCount(kept),
        lessThanOrEqualTo(5),
        reason: 'the cut run must fit what the earlier cells left',
      );
    });

    test('a section band and the blend modes read SOMETHING, not just …', () {
      // The three surfaces the review measured, at their real capacities.
      String shown(String text, int capacity) => verticalTextCellsWithin(
        verticalTextCells(text),
        capacityCells: capacity,
      ).map((c) => c.text).join();

      // SectionBandZone over a one-row run: 28px at 9pt.
      expect(shown('ACTION', 2), startsWith('A'));
      // LayerBlendModeChip(axis: vertical): the 58px slot at 9.5pt.
      for (final mode in ['Multiply', 'Color Dodge', 'Pass Through']) {
        expect(shown(mode, 4), startsWith(mode[0]), reason: mode);
      }
      // The x-sheet's 100px name slot at 11pt.
      expect(shown('Background rough', 7), startsWith('Back'));
    });

    test('a column that fits EXACTLY is never ellipsised', () {
      // A host sizing to the column's own preferred extent hands back
      // exactly n * naturalCellExtent — and in IEEE-754 that quotient
      // lands on n - 1ulp often enough to matter. A bare floor cut the
      // last cell off a column that fits perfectly.
      for (final fontSize in [9.0, 9.5, 11.0, 12.0]) {
        for (final lineHeight in [1.05, 1.15]) {
          final cellExtent = fontSize * lineHeight;
          for (var cells = 1; cells <= 24; cells += 1) {
            expect(
              verticalTextCapacityCells(
                mainExtent: cells * cellExtent,
                naturalCellExtent: cellExtent,
              ),
              cells,
              reason: '$cells cells at $fontSize/$lineHeight',
            );
          }
        }
      }
      // And it still refuses to over-count a span that is genuinely short.
      expect(
        verticalTextCapacityCells(mainExtent: 51.0, naturalCellExtent: 10.35),
        4,
      );
      expect(
        verticalTextCapacityCells(mainExtent: 0, naturalCellExtent: 10.35),
        0,
      );
    });

    test('no room for even one letter still yields the bare ellipsis', () {
      final kept = verticalTextCellsWithin(
        verticalTextCells('Multiply'),
        capacityCells: 1,
      );
      expect(kept.map((c) => c.text).toList(), ['…']);
    });

    test('no room at all yields nothing', () {
      expect(
        verticalTextCellsWithin(verticalTextCells('あい'), capacityCells: 0),
        isEmpty,
      );
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

    test(
      'the floor holds — packing never shrinks a glyph out of existence',
      () {
        expect(fitFor(12, 1).fontSize, 4);
        expect(fitFor(40, 1).fontSize, 4);
      },
    );

    test('no cells, no extent', () {
      expect(fitFor(0, 5).totalExtent, 0);
    });
  });

  // F-224: the SE row measures its dialogue down a column before drawing it
  // (`dialogueNaturalExtent`), so what a glyph is drawn at and what it is
  // measured at are one answer — the one this renderer draws.
  group('a turned glyph in a narrow column', () {
    // A line height that is not the glyph's width, so the two can be told
    // apart once the glyph lies down.
    const style = TextStyle(fontSize: 14, height: 1.5);
    const column = 10.0;

    test('is fitted ACROSS by its height and advances DOWN by its width', () {
      final painter = TextPainter(
        text: const TextSpan(text: 'ー', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(verticalGlyphCell('ー').form, VerticalGlyphForm.rotated);
      expect(painter.height, greaterThan(column), reason: 'fixture');
      expect(
        painter.width,
        isNot(closeTo(painter.height, 1)),
        reason: 'fixture',
      );
      final fit = column / painter.height;

      final spy = _SpyCanvas();
      double? advance;
      paintVerticalTextCell(
        spy,
        verticalGlyphCell('ー'),
        painter: painter,
        center: Offset.zero,
        fontSize: 14,
        setWord: paintScaledText,
        maxCrossExtent: column,
        alongColumnScale: (extent) {
          advance = extent;
          return 1;
        },
      );
      expect(
        spy.scales.single.$2,
        closeTo(fit, 1e-9),
        reason: 'lying down, its HEIGHT has to clear the column',
      );
      expect(
        advance,
        closeTo(painter.width * fit, 1e-9),
        reason: 'lying down, it runs its WIDTH down the column',
      );
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
        setWord: paintScaledText,
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
        setWord: paintScaledText,
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
        setWord: paintScaledText,
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
        setWord: paintScaledText,
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

  // 🚨ONE LAW for a text whichever way it is written (R9-rest, 세로쓰기 —
  // 유저 2026-10-06: 「그거 통합하면서 진행」). Where a column that wraps may
  // end is this table's to say ([verticalMayBreakBetween]) and where a line
  // may is the engine's own: so the table says what the engine does, of
  // every character asked here — and the engine is asked AGAIN every run,
  // never trusted from the day the sets were written (2026-10-07).
  group('a column breaks where a line would', () {
    /// Where the engine ends the first line of [text] — four letters fit.
    int firstLineEnd(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 10, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 40);
      final end = painter.getLineBoundary(const TextPosition(offset: 0)).end;
      painter.dispose();
      return end;
    }

    /// Whether the engine keeps [char] off a line's HEAD: fifth on a line
    /// of four, it takes the fourth letter down with it.
    bool keptOffAHead(String char) => firstLineEnd('ああああ$charあ') < 4;

    /// Whether the engine keeps [char] off a line's END: fourth on a line
    /// of four, it goes down with the letter after it.
    bool keptOffAnEnd(String char) => firstLineEnd('あああ$charああ') < 4;

    const asked = [
      // closing brackets and quotes
      '）', ')', '〕', '］', ']', '｝', '}', '〉', '》', '」', '』', '】', '〗', '〙',
      '〛', '｠', '｣', '〟', '〞', '’', '”', '»', '›',
      // opening brackets and quotes
      '（', '(', '〔', '［', '[', '｛', '{', '〈', '《', '「', '『', '【', '〖', '〘',
      '〚', '｟', '｢', '〝', '‘', '“', '«', '‹',
      // stops
      '、', '。', '，', '．', ',', '.', '､', '｡',
      // clause marks
      '？', '！', '?', '!', '‼', '⁇', '⁈', '⁉', '・', '･', '·', '：', '；', ':',
      ';',
      // repeat marks
      '々', 'ゝ', 'ゞ', 'ヽ', 'ヾ', '〻', '〃',
      // the long vowel mark and the small kana — free on a line
      'ー', 'ｰ', 'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ', 'っ', 'ゃ', 'ゅ', 'ょ', 'ゎ', 'ゕ',
      'ゖ', 'ァ', 'ィ', 'ゥ', 'ェ', 'ォ', 'ッ', 'ャ', 'ュ', 'ョ', 'ヮ', 'ヵ', 'ヶ',
      'ｧ', 'ｨ', 'ｩ', 'ｪ', 'ｫ', 'ｯ', 'ｬ', 'ｭ', 'ｮ',
      // dashes and leaders
      '〜', '～', '…', '‥', '―', '—', '–', '‐', '‑', '-', '゠', '＝', '=',
      // signs that follow a number
      '％', '%', '‰', '°', '′', '″', '℃', '¢',
      // signs that lead one
      '￥', '＄', r'$', '£', '€', '¥', '№', '＃', '#', '＠', '@', '〒',
      // others
      '＆', '&', '＊', '*', '／', '/', '＋', '+', '×', '÷', '※', '★', '☆', '○',
      '●', '◎', '△', '□', '♪', '→', '←', '↑', '↓',
      // voicing marks
      '゛', '゜', 'ﾞ', 'ﾟ',
      // letters
      'あ', '漢', 'ア', '한',
    ];

    test('white space is not what a column ends BEFORE — it hangs at the '
        'foot of its column, as a line\'s does — and a column may end '
        'after it', () {
      for (final space in [' ', '　']) {
        expect(verticalMayBreakBetween('あ', space), isFalse);
        expect(verticalMayBreakBetween(space, 'あ'), isTrue);
      }
    });

    test('⛔CONTROL: the engine IS asked, and answers both ways', () {
      expect(keptOffAHead('あ'), isFalse);
      expect(keptOffAnEnd('あ'), isFalse);
      expect(keptOffAHead('。'), isTrue);
      expect(keptOffAnEnd('。'), isFalse);
      expect(keptOffAHead('「'), isFalse);
      expect(keptOffAnEnd('「'), isTrue);
    });

    test('🚨what does not HEAD a line does not head a column — and what '
        'may, may', () {
      for (final char in asked) {
        expect(
          verticalMayBreakBetween('あ', char),
          !keptOffAHead(char),
          reason: 'before 「$char」',
        );
      }
    });

    test('🚨what does not END a line does not end a column — and what may, '
        'may', () {
      for (final char in asked) {
        expect(
          verticalMayBreakBetween(char, 'あ'),
          !keptOffAnEnd(char),
          reason: 'after 「$char」',
        );
      }
    });

    test('every character the table names is one of those asked', () {
      expect(asked.toSet(), containsAll(verticalNoColumnStartChars));
      expect(asked.toSet(), containsAll(verticalNoColumnEndChars));
    });

    // 🔬Measured with the rest: the engine lets these begin a line, so the
    // table lets them begin a column. Named, because a house style that
    // keeps them off would be a change of BOTH — the engine's is not ours
    // to set.
    test('the long vowel mark and the small kana may head either', () {
      for (final char in ['ー', 'っ', 'ゃ', 'ッ', 'ャ']) {
        expect(keptOffAHead(char), isFalse, reason: char);
        expect(verticalMayBreakBetween('あ', char), isTrue, reason: char);
      }
    });
  });
}
