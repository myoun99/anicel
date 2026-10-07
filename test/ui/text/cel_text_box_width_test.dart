import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/cel_text_box_width.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool) — 유저 2026-10-06: 「이부분 고정할지 비고정할지는
/// 도구설정에서 스왑가능」, and of the swap: 「상자 폭을 바꿔도 보이는 모양은
/// 그대로. 고정→자동이면 줄이 꺾이던 자리에 Enter가 들어갑니다」.
///
/// 🚨SO THE MEASURE IS THE LETTERS: every letter stands, on the canvas,
/// exactly where it stood. What a swap changes is what the next letter
/// typed does.
///
/// ⚠️The numbers are the TEST FONT's: every glyph a box one letter-size
/// wide and tall, so 「ab」 at size 20 with a line pitch of 1 is 40 by 20.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plain = TextLetterStyle(fontSize: 20);
  const red = TextLetterStyle(fontSize: 20, color: 0xFFFF0000);

  CelTextContent said(
    List<CelTextSpan> spans, {
    double x = 100,
    double y = 50,
    double? wrapWidth,
    double turn = 0,
    TextCelAlign align = TextCelAlign.left,
    bool vertical = false,
  }) => CelTextContent(
    spans: spans,
    anchor: CanvasPoint(x: x, y: y),
    wrapWidth: wrapWidth,
    rotationDegrees: turn,
    align: align,
    lineHeight: 1,
    vertical: vertical,
  );

  CelTextSpan run(String words, [TextLetterStyle style = plain]) =>
      CelTextSpan(text: words, style: style);

  /// Where every letter of [content] that is not a break stands on the
  /// canvas: the four corners of its box, in reading order.
  List<List<ui.Offset>> lettersOf(CelTextContent content) {
    final layout = layoutCelText(content);
    addTearDown(layout.dispose);
    final text = content.text;
    return [
      for (var at = 0; at < text.length; at += 1)
        if (text[at] != '\n')
          for (final box in layout.selectionRects(at, at + 1))
            [
              layout.toCanvas(box.topLeft),
              layout.toCanvas(box.topRight),
              layout.toCanvas(box.bottomRight),
              layout.toCanvas(box.bottomLeft),
            ],
    ];
  }

  /// That [after] sets every letter where [before] sets it — to a
  /// thousandth of a pixel: the engine keeps its lines in single precision.
  void expectSameLetters(CelTextContent before, CelTextContent after) {
    final was = lettersOf(before);
    final now = lettersOf(after);
    expect(now, hasLength(was.length));
    expect(was, isNotEmpty, reason: '⛔fixture: there are letters to compare');
    for (var letter = 0; letter < was.length; letter += 1) {
      for (var corner = 0; corner < 4; corner += 1) {
        expect(
          (now[letter][corner] - was[letter][corner]).distance,
          lessThan(1e-3),
          reason:
              'letter $letter corner $corner: ${was[letter][corner]} → '
              '${now[letter][corner]}',
        );
      }
    }
  }

  group('a text that grows, made a box', () {
    test('🚨is as wide as the next whole pixel PAST its longest line and '
        'hangs where its lines stand: no letter moves', () {
      // 「abcd」 is 80 wide.
      final growing = said([run('abcd\nef')]);

      final boxed = celTextBoxed(growing);

      expect(boxed.wrapWidth, 81);
      expect(boxed.anchor, CanvasPoint(x: 100, y: 50));
      expect(boxed.text, 'abcd\nef');
      expectSameLetters(growing, boxed);
    });

    test('🚨a CENTRED one: its anchor goes from the middle of its lines to '
        'the box\'s corner', () {
      final growing = said([run('abcd\nef')], align: TextCelAlign.center);

      final boxed = celTextBoxed(growing);

      expect(boxed.wrapWidth, 81);
      expect(boxed.anchor, CanvasPoint(x: 59.5, y: 50));
      expect(boxed.align, TextCelAlign.center);
      expectSameLetters(growing, boxed);
    });

    test('a RIGHT-aligned one: from the end of its lines', () {
      final growing = said([run('abcd\nef')], align: TextCelAlign.right);

      final boxed = celTextBoxed(growing);

      expect(boxed.wrapWidth, 81);
      expect(boxed.anchor, CanvasPoint(x: 19, y: 50));
      expectSameLetters(growing, boxed);
    });

    for (final align in TextCelAlign.values) {
      test('🚨a TRACKED text, its width not whole: up to the next pixel, and '
          'still no letter moves (${align.name})', () {
        // Three letters of 20.3, each with 0.37 of tracking: 62.01 wide.
        // ⚠️The case that found the engine's rule: a line that FILLS its
        // width is not aligned at all — it stood half its tracking off the
        // others — so a box exactly as wide as the longest line moved it.
        const odd = TextLetterStyle(fontSize: 20.3, letterSpacing: 0.37);
        final growing = said([run('abc\nd', odd)], align: align);

        final boxed = celTextBoxed(growing);

        expect(boxed.wrapWidth, 63);
        expectSameLetters(growing, boxed);
      });

      test('a line that is a whole number of pixels wide still gets a pixel '
          'of room (${align.name})', () {
        const tracked = TextLetterStyle(fontSize: 20, letterSpacing: 10);
        // Three letters of 20, each with 10 of tracking: 90 wide.
        final growing = said([run('abc\nd', tracked)], align: align);

        final boxed = celTextBoxed(growing);

        expect(boxed.wrapWidth, 91);
        expectSameLetters(growing, boxed);
      });
    }

    test('a TURNED one keeps its turn: the corner is found along the '
        'text\'s own line', () {
      final growing = said(
        [run('abcd\nef')],
        align: TextCelAlign.center,
        turn: 90,
      );

      final boxed = celTextBoxed(growing);

      expect(boxed.rotationDegrees, 90);
      // The lines ran 40 either side of the anchor, DOWN the canvas, and
      // the box is 81: its corner is 40.5 up it.
      expect(boxed.anchor.x, closeTo(100, 1e-9));
      expect(boxed.anchor.y, closeTo(9.5, 1e-9));
      expectSameLetters(growing, boxed);
    });

    test('a line that ends in a space is as wide as the space makes it', () {
      final growing = said([run('ab \ncd')], align: TextCelAlign.right);

      final boxed = celTextBoxed(growing);

      expect(boxed.wrapWidth, 61);
      expectSameLetters(growing, boxed);
    });

    test('one that is a box already is itself', () {
      final box = said([run('ab cd')], wrapWidth: 70);

      expect(identical(celTextBoxed(box), box), isTrue);
    });

    test('⛔one with NO letters has no line to be as wide as: itself', () {
      final empty = said(const []);

      expect(identical(celTextBoxed(empty), empty), isTrue);
    });
  });

  group('a box, made a text that grows', () {
    for (final (align, x) in [
      (TextCelAlign.left, 100.0),
      (TextCelAlign.center, 135.0),
      (TextCelAlign.right, 170.0),
    ]) {
      test('🚨a break is typed in where a line wrapped, AFTER the space it '
          'wrapped at — and no letter moves (${align.name})', () {
        // 70 wide: 「ab 」 and then 「cd」.
        final box = said([run('ab cd')], wrapWidth: 70, align: align);

        final growing = celTextUnboxed(box);

        expect(growing.wrapWidth, isNull);
        expect(growing.text, 'ab \ncd');
        expect(growing.anchor, CanvasPoint(x: x, y: 50));
        expect(growing.align, align);
        expectSameLetters(box, growing);
      });

      test('🚨a TRACKED one: no letter moves — its longest line too '
          '(${align.name})', () {
        const tracked = TextLetterStyle(fontSize: 20, letterSpacing: 10);
        // 「abc 」 is 120 with its space, 90 without; 「de」 is 60.
        final box = said(
          [run('abc de', tracked)],
          wrapWidth: 130,
          align: align,
        );

        final growing = celTextUnboxed(box);

        expect(growing.text, 'abc \nde');
        expectSameLetters(box, growing);
      });
    }

    test('a word broken in its middle gets its breaks there', () {
      final box = said([run('abcdefg')], wrapWidth: 70);

      final growing = celTextUnboxed(box);

      expect(growing.text, 'abc\ndef\ng');
      expectSameLetters(box, growing);
    });

    test('⛔a break that was TYPED is left as it is — and an empty line '
        'with it', () {
      final box = said([run('ab\n\ncd ef')], wrapWidth: 70);

      final growing = celTextUnboxed(box);

      expect(growing.text, 'ab\n\ncd \nef');
      expectSameLetters(box, growing);
    });

    test('a box nothing wrapped in keeps its letters as they are', () {
      final box = said([run('ab')], wrapWidth: 70, align: TextCelAlign.right);

      final growing = celTextUnboxed(box);

      expect(growing.text, 'ab');
      expect(growing.anchor, CanvasPoint(x: 170, y: 50));
      expectSameLetters(box, growing);
    });

    test('the break wears what the letter before it wears', () {
      final box = said([run('ab ', red), run('cd')], wrapWidth: 70);

      final growing = celTextUnboxed(box);

      expect(growing.spans, [run('ab \n', red), run('cd')]);
    });

    test('a TURNED one keeps its turn', () {
      final box = said(
        [run('ab cd')],
        wrapWidth: 70,
        align: TextCelAlign.right,
        turn: 90,
      );

      final growing = celTextUnboxed(box);

      expect(growing.rotationDegrees, 90);
      expect(growing.anchor.x, closeTo(100, 1e-9));
      expect(growing.anchor.y, closeTo(120, 1e-9));
      expectSameLetters(box, growing);
    });

    test('one that grows already is itself', () {
      final growing = said([run('ab cd')]);

      expect(identical(celTextUnboxed(growing), growing), isTrue);
    });

    test('one with no letters is a text with none, where its lines would '
        'stand', () {
      final box = said(const [], wrapWidth: 70, align: TextCelAlign.center);

      final growing = celTextUnboxed(box);

      expect(growing.wrapWidth, isNull);
      expect(growing.isEmpty, isTrue);
      expect(growing.anchor, CanvasPoint(x: 135, y: 50));
    });
  });

  // 세로쓰기 (유저 2026-10-06). The swap is the same law read down the
  // columns: no letter moves.
  group('written in COLUMNS', () {
    for (final align in TextCelAlign.values) {
      for (final turn in [0.0, 30.0]) {
        test('🚨a text that grows, made a box: as LONG as the next whole '
            'pixel past its longest column, and no letter moves — '
            '${align.name}, turned $turn', () {
          final before = said(
            [run('abc\nd')],
            align: align,
            turn: turn,
            vertical: true,
          );

          final boxed = celTextBoxed(before);

          // 「abc」 lies down the column: 60 long.
          expect(boxed.wrapWidth, 61);
          expect(boxed.vertical, isTrue);
          expectSameLetters(before, boxed);
        });

        test('🚨a box, made a text that grows: a break where a column ended '
            'for want of room, and no letter moves — ${align.name}, turned '
            '$turn', () {
          final before = said(
            [run('あいうえおかき')],
            wrapWidth: 60,
            align: align,
            turn: turn,
            vertical: true,
          );

          final grown = celTextUnboxed(before);

          expect(grown.wrapWidth, isNull);
          expect(grown.text, 'あいう\nえおか\nき');
          expectSameLetters(before, grown);
        });
      }
    }
  });

  group('a text written THE OTHER WAY, where it stands', () {
    ui.Offset cornerOf(CelTextContent content) {
      final layout = layoutCelText(content);
      addTearDown(layout.dispose);
      return layout.toCanvas(layout.block.topLeft);
    }

    ui.Size blockOf(CelTextContent content) {
      final layout = layoutCelText(content);
      addTearDown(layout.dispose);
      return layout.block.size;
    }

    for (final align in TextCelAlign.values) {
      for (final turn in [0.0, 30.0]) {
        test('🚨the top left corner of its letters\' block stays where it is '
            '— into columns and back — ${align.name}, turned $turn', () {
          final lines = said(
            [run('あいうえ\nおか')],
            align: align,
            turn: turn,
          );
          final corner = cornerOf(lines);

          final columns = celTextWrittenAs(lines, vertical: true);

          expect(columns.vertical, isTrue);
          expect(columns.text, lines.text);
          expect((cornerOf(columns) - corner).distance, lessThan(1e-9));
          expect(
            blockOf(columns),
            const ui.Size(40, 80),
            reason: '⛔fixture: it IS set the other way',
          );

          final back = celTextWrittenAs(columns, vertical: false);

          expect(back.vertical, isFalse);
          expect((cornerOf(back) - corner).distance, lessThan(1e-9));
          expect(blockOf(back), blockOf(lines));
        });
      }
    }

    test('🚨a BOX keeps its shape as near as a box can: what it was TALL is '
        'what its columns are LONG', () {
      // Three letters a line: two lines, 60 by 40.
      final box = said([run('あいうえおか')], wrapWidth: 60);
      expect(blockOf(box), const ui.Size(60, 40), reason: '⛔fixture');

      final columns = celTextWrittenAs(box, vertical: true);

      // Columns 40 long hold two letters each: three columns, 60 by 40.
      expect(columns.wrapWidth, 40);
      expect(blockOf(columns), const ui.Size(60, 40));
      expect(celTextWrittenAs(columns, vertical: false).wrapWidth, 60);
    });

    test('a text that grows stays one that grows', () {
      expect(
        celTextWrittenAs(said([run('123')]), vertical: true).wrapWidth,
        isNull,
      );
    });

    test('written that way already, it is itself', () {
      final lines = said([run('123')]);
      final columns = said([run('123')], vertical: true);

      expect(celTextWrittenAs(lines, vertical: false), same(lines));
      expect(celTextWrittenAs(columns, vertical: true), same(columns));
    });
  });

  group('there and back', () {
    for (final align in TextCelAlign.values) {
      test('a text made a box and made to grow again is the text it was '
          '(${align.name})', () {
        final growing = said([run('abcd\nef')], align: align);

        expect(celTextUnboxed(celTextBoxed(growing)), growing);
      });
    }

    test('a box made to grow and made a box again wraps nowhere: its lines '
        'are typed now — and no letter has moved', () {
      final box = said([run('ab cd')], wrapWidth: 70);

      final again = celTextBoxed(celTextUnboxed(box));

      expect(again.text, 'ab \ncd');
      // A pixel past its longest line, the space at its end counted.
      expect(again.wrapWidth, 61);
      expectSameLetters(box, again);
    });
  });

  group('where a line ends for want of room', () {
    List<int> wrapPlaces(CelTextContent content) {
      final layout = layoutCelText(content);
      addTearDown(layout.dispose);
      return layout.wrapPlaces;
    }

    test('is the first letter of the line after', () {
      expect(wrapPlaces(said([run('ab cd')], wrapWidth: 70)), [3]);
      expect(wrapPlaces(said([run('abcdefg')], wrapWidth: 70)), [3, 6]);
    });

    test('⛔is never where a break was typed', () {
      expect(wrapPlaces(said([run('ab\ncd')], wrapWidth: 70)), isEmpty);
      expect(wrapPlaces(said([run('ab\n\ncd ef')], wrapWidth: 70)), [7]);
      expect(wrapPlaces(said([run('ab\n')], wrapWidth: 70)), isEmpty);
    });

    test('a text that grows has none', () {
      expect(wrapPlaces(said([run('ab cd ef gh')])), isEmpty);
    });
  });
}
