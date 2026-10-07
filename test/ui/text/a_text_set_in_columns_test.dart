import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/painting.dart' show TextAffinity, TextPosition;
import 'package:flutter_test/flutter_test.dart';

/// R9-rest, 세로쓰기 (유저 2026-10-06: 「어차피 타임시트나 x시트에서
/// 가로쓰기/세로표기같은거 한거 많으니 그거 통합하면서 진행해도될듯」): A TEXT
/// OF A CEL SET IN COLUMNS — its letters top to bottom, its columns from
/// the right to the left — and everything the tool reads off a text set:
/// its block, its caret, the letter under a press, where a box broke it.
///
/// WHAT each letter does in a column is the app's one table's
/// (`vertical_writing_test.dart` pins it); here, WHERE the cells stand.
///
/// ⚠️The numbers are the TEST FONT's: every glyph is a box one letter-size
/// wide and tall, so at a pitch of 1 and size 20 a column is 20 wide and a
/// letter standing in it takes 20 of its length.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CelTextSpan run(String words, {double size = 20, double tracking = 0}) =>
      CelTextSpan(
        text: words,
        style: TextLetterStyle(fontSize: size, letterSpacing: tracking),
      );

  CelTextLayout set(
    List<CelTextSpan> spans, {
    double x = 0,
    double y = 0,
    double? wrapWidth,
    double turn = 0,
    TextCelAlign align = TextCelAlign.left,
    double lineHeight = 1,
    TextLetterStyle nextLetterStyle = const TextLetterStyle(fontSize: 20),
  }) {
    final layout = layoutCelText(
      CelTextContent(
        spans: spans,
        anchor: CanvasPoint(x: x, y: y),
        wrapWidth: wrapWidth,
        rotationDegrees: turn,
        align: align,
        lineHeight: lineHeight,
        vertical: true,
      ),
      nextLetterStyle: nextLetterStyle,
    );
    addTearDown(layout.dispose);
    return layout;
  }

  ui.Rect at(double left, double top, double width, double height) =>
      ui.Rect.fromLTWH(left, top, width, height);

  /// The place of the one letter at [offset].
  ui.Rect letter(CelTextLayout layout, int offset) =>
      layout.selectionRects(offset, offset + 1).single;

  int placeAt(CelTextLayout layout, double x, double y) =>
      layout.positionAt(ui.Offset(x, y)).offset;

  group('a text that grows', () {
    test('🚨runs DOWN from its anchor, one column wide: its block hangs to '
        'the LEFT of the anchor, as long as its letters', () {
      final layout = set([run('あいう')]);

      expect(layout.block, at(-20, 0, 20, 60));
      expect(letter(layout, 0), at(-20, 0, 20, 20));
      expect(letter(layout, 1), at(-20, 20, 20, 20));
      expect(letter(layout, 2), at(-20, 40, 20, 20));
    });

    test('a break typed into it opens the next column to the LEFT', () {
      final layout = set([run('あい\nう')]);

      expect(layout.block, at(-40, 0, 40, 40));
      expect(letter(layout, 0), at(-20, 0, 20, 20));
      expect(letter(layout, 3), at(-40, 0, 20, 20));
      expect(layout.wrapPlaces, isEmpty, reason: 'typed, not for want of room');
    });

    test('stands ABOUT its anchor as its alignment says, read down the '
        'column: its head, its middle or its foot', () {
      expect(set([run('あいう')], align: TextCelAlign.center).block, at(-20, -30, 20, 60));
      expect(set([run('あいう')], align: TextCelAlign.right).block, at(-20, -60, 20, 60));
    });

    test('a shorter column stands in the block as the alignment says', () {
      final middle = set([run('あいう\nえ')], align: TextCelAlign.center);
      final foot = set([run('あいう\nえ')], align: TextCelAlign.right);

      expect(middle.block, at(-40, -30, 40, 60));
      expect(letter(middle, 4), at(-40, -10, 20, 20));
      expect(foot.block, at(-40, -60, 40, 60));
      expect(letter(foot, 4), at(-40, -20, 20, 20));
    });

    test('a column is as wide as the pitch of its LARGEST letter', () {
      final layout = set([
        run('あ'),
        run('い', size: 40),
        run('\nう'),
      ], lineHeight: 1.5);

      // The first column: 40 × 1.5; the second: 20 × 1.5.
      expect(layout.block.width, 60 + 30);
      expect(letter(layout, 0), at(-60, 0, 60, 20));
      expect(letter(layout, 1), at(-60, 20, 60, 40));
      expect(letter(layout, 3), at(-90, 0, 30, 20));
    });

    test('🚨…its largest letter WHEREVER in the column it stands — first, '
        'and the smaller ones after it', () {
      final layout = set([
        run('い', size: 40),
        run('あ'),
        run('\nう'),
      ], lineHeight: 1.5);

      expect(layout.block.width, 60 + 30);
      expect(letter(layout, 0), at(-60, 0, 60, 40));
      expect(letter(layout, 1), at(-60, 40, 60, 20));
    });

    test('tracking is room AFTER a letter, down its column', () {
      final layout = set([run('あいう', tracking: 5)]);

      expect(layout.block, at(-20, 0, 20, 75));
      expect(letter(layout, 1), at(-20, 25, 20, 25));
    });

    test('a column a break opened and left EMPTY is as wide as the letters '
        'of the break', () {
      final layout = set([run('あ\n', size: 30), run('\nう')]);

      // あ's column (30) · the empty one, opened by a size-30 break (30) ·
      // う's (20).
      expect(layout.block.width, 80);
      expect(letter(layout, 3), at(-80, 0, 20, 20));
    });
  });

  group('a text in a box', () {
    test('🚨hangs from its anchor by its top RIGHT corner, its columns as '
        'long as the box, and begins the next where one is full', () {
      final layout = set([run('あいうえお')], wrapWidth: 40);

      expect(layout.block, at(-60, 0, 60, 40));
      expect(letter(layout, 2), at(-40, 0, 20, 20));
      expect(letter(layout, 4), at(-60, 0, 20, 20));
      expect(layout.wrapPlaces, [2, 4]);
    });

    test('is as long as the box whatever it holds, and the alignment places '
        'each column inside that length', () {
      final layout = set(
        [run('あ')],
        wrapWidth: 100,
        align: TextCelAlign.right,
      );

      expect(layout.block, at(-20, 0, 20, 100));
      expect(letter(layout, 0), at(-20, 80, 20, 20));
    });

    test('🚨a full stop does not HEAD a column: the letter before it goes '
        'to the next column with it', () {
      final layout = set([run('あい。う')], wrapWidth: 40);

      // あ | い。 | う — and not あい | 。う.
      expect(layout.wrapPlaces, [1, 3]);
      expect(letter(layout, 2).left, -40);
    });

    test('an opening bracket does not END a column', () {
      final layout = set([run('あ「い')], wrapWidth: 40);

      expect(layout.wrapPlaces, [1]);
    });

    test('🚨white space at a column\'s foot HANGS past the box — it is not '
        'what has to fit, so the letter before it stays in its column', () {
      final layout = set([run('あい うえ')], wrapWidth: 40);

      // あい fill the box, the space hangs past its foot, う heads the next.
      expect(layout.wrapPlaces, [3]);
      expect(letter(layout, 1), at(-20, 20, 20, 20));
      expect(letter(layout, 2).top, 40, reason: 'the space, past the foot');
      expect(letter(layout, 3), at(-40, 0, 20, 20));
    });

    test('🚨a NUMBER does not part across two columns — so a break typed '
        'where a column ended can never make two of its digits a pair', () {
      final layout = set([run('あ1234')], wrapWidth: 60);

      // あ | 1234 — past the foot of its column rather than cut.
      expect(layout.wrapPlaces, [1]);
    });

    test('⛔CONTROL: letters that may part do, where the box is full', () {
      expect(set([run('あいうえ')], wrapWidth: 40).wrapPlaces, [2]);
    });

    test('a Latin phrase lies DOWN the column, and breaks between its words '
        '— the space hanging at the foot of the column it ends', () {
      // 「ab 」 is 60 long lying down, 「cd」 40: a box 70 long holds the
      // first with its space, and not both.
      final layout = set([run('ab cd')], wrapWidth: 70);

      expect(layout.wrapPlaces, [3]);
      expect(layout.selectionRects(0, 3).single, at(-20, 0, 20, 60));
      expect(layout.selectionRects(3, 5).single, at(-40, 0, 20, 40));
    });

    test('cells that may not part and are longer than the box run past its '
        'foot rather than break', () {
      final layout = set([run('あ。。。')], wrapWidth: 40);

      expect(layout.wrapPlaces, isEmpty);
      expect(layout.block, at(-20, 0, 20, 40));
    });
  });

  group('what the table makes of a letter', () {
    test('two digits stand SIDE BY SIDE in one cell', () {
      final layout = set([run('A12')]);

      // 「12」 is one cell: both its digits answer with places in it.
      expect(letter(layout, 1).top, letter(layout, 2).top);
      expect(letter(layout, 1).right, letter(layout, 2).left);
      expect(letter(layout, 1).left, lessThan(letter(layout, 2).left));
    });

    test('a Latin word lies down: its letters follow one another DOWN the '
        'column, each as long as it is wide', () {
      final layout = set([run('ab')]);

      expect(layout.block, at(-20, 0, 20, 40));
      expect(letter(layout, 0), at(-20, 0, 20, 20));
      expect(letter(layout, 1), at(-20, 20, 20, 20));
    });
  });

  group('the caret', () {
    test('🚨is a hairline ACROSS its column, at the head of the letter it '
        'stands before', () {
      final layout = set([run('あいう')]);

      expect(layout.caretRect(const TextPosition(offset: 0)), at(-20, 0, 20, 0));
      expect(layout.caretRect(const TextPosition(offset: 1)), at(-20, 20, 20, 0));
      expect(layout.caretRect(const TextPosition(offset: 3)), at(-20, 60, 20, 0));
    });

    test('after a break it stands at the head of the column the break '
        'opened — an empty one too', () {
      final layout = set([run('あ\n')]);

      expect(layout.caretRect(const TextPosition(offset: 1)), at(-20, 20, 20, 0));
      expect(layout.caretRect(const TextPosition(offset: 2)), at(-40, 0, 20, 0));
    });

    test('where a box broke the text it stands at the head of the NEXT '
        'column', () {
      final layout = set([run('あいうえ')], wrapWidth: 40);

      expect(layout.caretRect(const TextPosition(offset: 2)), at(-40, 0, 20, 0));
    });

    test('inside a word lying down it stands between its letters, across '
        'the column', () {
      final layout = set([run('abc')]);

      expect(layout.caretRect(const TextPosition(offset: 2)), at(-20, 40, 20, 0));
    });

    test('between two digits side by side it stands between them — a '
        'hairline DOWN their cell', () {
      final layout = set([run('12')]);
      final caret = layout.caretRect(const TextPosition(offset: 1));

      expect(caret.width, 0);
      expect(caret.height, greaterThan(0));
      expect(caret.left, letter(layout, 1).left);
    });

    test('a text with NO letters has one: across a column as wide as the '
        'letter about to be typed', () {
      final layout = set(
        const [],
        nextLetterStyle: const TextLetterStyle(fontSize: 30),
        lineHeight: 1.5,
      );

      expect(layout.block, at(-45, 0, 45, 0));
      expect(layout.caretRect(const TextPosition(offset: 0)), at(-45, 0, 45, 0));
    });
  });

  group('the letter under a press', () {
    test('🚨the column by where the point is ACROSS, the place by how far '
        'DOWN — the nearer end of the letter it is on', () {
      final layout = set([run('あい\nうえ')]);

      expect(placeAt(layout, -10, 5), 0);
      expect(placeAt(layout, -10, 15), 1);
      expect(placeAt(layout, -10, 35), 2, reason: 'the end of its column');
      expect(placeAt(layout, -30, 5), 3, reason: 'the next column');
      expect(placeAt(layout, -30, 35), 5);
    });

    test('a point beside every column is on the nearest; past a column\'s '
        'foot, at its end', () {
      final layout = set([run('あい\nう')]);

      expect(placeAt(layout, 50, 5), 0, reason: 'right of the first');
      expect(placeAt(layout, -500, 5), 3, reason: 'left of the last');
      expect(placeAt(layout, -30, 500), 4, reason: 'under the last');
      expect(placeAt(layout, -10, 500), 2, reason: 'under the first');
    });

    test('the foot of a column the BOX ended is that column\'s — said '
        'upstream — though the place is the next one\'s head too', () {
      final layout = set([run('あいうえ')], wrapWidth: 40);
      final position = layout.positionAt(const ui.Offset(-10, 500));

      expect(position.offset, 2);
      expect(position.affinity, TextAffinity.upstream);
    });

    test('inside a word lying down, the place between the letters nearest', () {
      final layout = set([run('abc')]);

      expect(placeAt(layout, -10, 22), 1);
      expect(placeAt(layout, -10, 38), 2);
    });

    test('is asked in CANVAS points: of a text turned and standing away '
        'from the origin', () {
      // A quarter turn clockwise: down the column is to the LEFT on the
      // canvas, and the next column is DOWN it.
      final layout = set([run('あい')], x: 100, y: 50, turn: 90);

      expect(placeAt(layout, 100 - 5, 50 - 10), 0);
      expect(placeAt(layout, 100 - 35, 50 - 10), 2);
    });
  });

  group('the letters being composed', () {
    test('wear their mark to the RIGHT of their column', () {
      final layout = set([run('あいう')]);

      expect(layout.marksBeside(1, 3), [
        (from: const ui.Offset(0, 20), to: const ui.Offset(0, 40)),
        (from: const ui.Offset(0, 40), to: const ui.Offset(0, 60)),
      ]);
    });
  });

  test('⛔CONTROL: the very text set in LINES is another block altogether, '
      'and marks its letters underneath', () {
    final layout = layoutCelText(
      CelTextContent(
        spans: [run('あいう')],
        anchor: CanvasPoint(x: 0, y: 0),
        lineHeight: 1,
      ),
    );
    addTearDown(layout.dispose);

    expect(layout.block, at(0, 0, 60, 20));
    expect(layout.marksBeside(0, 3), [
      (from: const ui.Offset(0, 20), to: const ui.Offset(60, 20)),
    ]);
  });
}
