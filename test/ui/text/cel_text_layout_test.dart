import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/painting.dart' show TextPosition;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';

/// R9-rest (the text tool): A TEXT OF A CEL, SET. `layoutCelText` is where
/// what a person chose — letters in runs, a size each, a box or none, a
/// turn — becomes where the letters ARE, and the box it is edited by, its
/// caret and the letter a press lands on are all read off it.
///
/// ⚠️The numbers are the TEST FONT's: flutter_test sets every glyph as a
/// box one letter-size wide and tall (three quarters of it above the
/// baseline), so at a line pitch of 1 a line is exactly as tall as its
/// letters and 「ab」 at size 20 is 40 by 20. A test that needs the app's
/// own faces loads them and says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CelTextSpan run(
    String words, {
    double size = 20,
    double tracking = 0,
    int color = 0xFF000000,
    int? outline,
    double outlineWidth = 0,
    bool bold = false,
    String? family,
  }) => CelTextSpan(
    text: words,
    style: TextLetterStyle(
      fontFamily: family,
      fontSize: size,
      letterSpacing: tracking,
      color: color,
      outlineColor: outline,
      outlineWidth: outlineWidth,
      bold: bold,
    ),
  );

  CelTextLayout set(
    List<CelTextSpan> spans, {
    double x = 0,
    double y = 0,
    double? wrapWidth,
    double turn = 0,
    TextCelAlign align = TextCelAlign.left,
    double lineHeight = 1,
    int? background,
    TextLetterStyle nextLetterStyle = const TextLetterStyle(),
  }) {
    final layout = layoutCelText(
      CelTextContent(
        spans: spans,
        anchor: CanvasPoint(x: x, y: y),
        wrapWidth: wrapWidth,
        rotationDegrees: turn,
        align: align,
        lineHeight: lineHeight,
        backgroundColor: background,
      ),
      nextLetterStyle: nextLetterStyle,
    );
    addTearDown(layout.dispose);
    return layout;
  }

  Matcher near(ui.Offset point) => isA<ui.Offset>()
      .having((o) => o.dx, 'dx', closeTo(point.dx, 1e-9))
      .having((o) => o.dy, 'dy', closeTo(point.dy, 1e-9));

  /// [layout] drawn onto a [width]×[height] canvas, as premultiplied RGBA.
  Future<Uint8List> drawn(CelTextLayout layout, int width, int height) async {
    final recorder = ui.PictureRecorder();
    layout.paint(ui.Canvas(recorder));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  List<int> pixel(Uint8List bytes, int width, int x, int y) =>
      bytes.sublist((y * width + x) * 4, (y * width + x) * 4 + 4);

  group('a text that grows', () {
    test('is as wide as its letters and stands ABOUT its anchor, as its '
        'alignment says', () {
      expect(
        set([run('abc')]).block,
        const ui.Rect.fromLTWH(0, 0, 60, 20),
        reason: 'left: the lines start at the anchor',
      );
      expect(
        set([run('abc')], align: TextCelAlign.center).block,
        const ui.Rect.fromLTWH(-30, 0, 60, 20),
        reason: 'centre: the anchor is their middle',
      );
      expect(
        set([run('abc')], align: TextCelAlign.right).block,
        const ui.Rect.fromLTWH(-60, 0, 60, 20),
        reason: 'right: they end at it',
      );
    });

    test('breaks only where a break was typed', () {
      expect(
        set([run('abcdefghijklmnopqrstuvwxyz')]).block,
        const ui.Rect.fromLTWH(0, 0, 26 * 20, 20),
        reason: 'one line, however long',
      );
      expect(
        set([run('ab\ncde')]).block,
        const ui.Rect.fromLTWH(0, 0, 60, 40),
      );
    });

    test('is DRAWN where it stands: a centred text on both sides of its '
        'anchor', () async {
      final bytes = await drawn(
        set(
          [run('ab', color: 0xFF0A141E)],
          x: 50,
          y: 10,
          align: TextCelAlign.center,
        ),
        100,
        40,
      );

      // The letters run from 30 to 70.
      expect(pixel(bytes, 100, 35, 20), [10, 20, 30, 255]);
      expect(pixel(bytes, 100, 65, 20), [10, 20, 30, 255]);
      expect(pixel(bytes, 100, 25, 20), [0, 0, 0, 0]);
      expect(pixel(bytes, 100, 75, 20), [0, 0, 0, 0]);
    });

    test('a shorter line stands inside the block as the alignment says', () {
      // 「abcd」 over 「ab」: the short line's first letter.
      ui.Rect second(TextCelAlign align) => set([
        run('abcd\nab'),
      ], align: align).caretRect(const TextPosition(offset: 5));

      expect(second(TextCelAlign.left).left, 0);
      expect(second(TextCelAlign.center).left, -40 + 20);
      expect(second(TextCelAlign.right).left, -80 + 40);
    });
  });

  group('🚨a text that grows, TRACKED: every line stands where the alignment '
      'puts it — the longest too', () {
    // 🔬Measured 2026-10-06: the engine aligns a line only in a width WIDER
    // than the line, and one that fills its width is left where a
    // left-aligned line stands — half its tracking in. A text that grows
    // is as wide as its longest line, so that line stood half its tracking
    // to the right of the rest. It is set with a pixel of room now.
    //
    // 「abc」 at 20 tracked by 10 is 90 wide; 「de」 untracked is 40.
    CelTextLayout tracked(TextCelAlign align) => set([
      run('abc\n', tracking: 10),
      run('de'),
    ], align: align);

    ({double left, double right}) line(CelTextLayout layout, int from, int to) {
      final boxes = layout.selectionRects(from, to);
      return (left: boxes.first.left, right: boxes.last.right);
    }

    test('centred: each line has its middle on the anchor', () {
      final layout = tracked(TextCelAlign.center);

      expect(layout.block, const ui.Rect.fromLTWH(-45, 0, 90, 40));
      final longest = line(layout, 0, 3);
      final shorter = line(layout, 4, 6);
      expect(longest.left, closeTo(-45, 1e-3));
      expect(longest.right, closeTo(45, 1e-3));
      expect(shorter.left, closeTo(-20, 1e-3));
      expect(shorter.right, closeTo(20, 1e-3));
    });

    test('set to the right: each line ends on the anchor', () {
      final layout = tracked(TextCelAlign.right);

      expect(layout.block, const ui.Rect.fromLTWH(-90, 0, 90, 40));
      expect(line(layout, 0, 3).right, closeTo(0, 1e-3));
      expect(line(layout, 0, 3).left, closeTo(-90, 1e-3));
      expect(line(layout, 4, 6).right, closeTo(0, 1e-3));
    });

    test('the room is the engine\'s to align in and no part of the text: '
        'the block is as wide as the longest line, to the pixel', () {
      for (final align in TextCelAlign.values) {
        expect(tracked(align).block.width, 90, reason: align.name);
      }
    });

    test('the caret and a press are measured where the letters are', () {
      final layout = tracked(TextCelAlign.right);

      // After 「abc」, on the first line: at the anchor.
      expect(
        layout.caretRect(const TextPosition(offset: 3)).left,
        closeTo(0, 1e-3),
      );
      // 「b」 runs from -60 to -30: a press either side of its middle is
      // nearest that side's edge — to the half pixel, which is less than
      // the room the letters' own box begins before the block.
      expect(layout.positionAt(const ui.Offset(-45.5, 10)).offset, 1);
      expect(layout.positionAt(const ui.Offset(-44.5, 10)).offset, 2);
    });

    test('it is DRAWN there: the longest line ends at the anchor by its '
        'last letter\'s box, as the shorter line does', () async {
      final bytes = await drawn(
        set(
          [run('abc\n', tracking: 10), run('de')],
          x: 100,
          align: TextCelAlign.right,
        ),
        110,
        40,
      );
      const ink = [0, 0, 0, 255];
      const none = [0, 0, 0, 0];

      // A letter's tracking is set after it, in its own box: 「c」's box
      // runs from 70 to the anchor at 100, its ink from 70 to 90. (Left
      // half its tracking out, the ink ran from 75 to 95.) 「e」, untracked,
      // runs to the anchor itself.
      expect(pixel(bytes, 110, 72, 10), ink);
      expect(pixel(bytes, 110, 88, 10), ink);
      expect(pixel(bytes, 110, 93, 10), none);
      expect(pixel(bytes, 110, 102, 10), none);
      expect(pixel(bytes, 110, 98, 30), ink);
      expect(pixel(bytes, 110, 102, 30), none);
    });
  });

  group('a text in a box', () {
    test('is as wide as the box, hangs from its anchor and wraps at its '
        'width', () {
      final boxed = set([run('abcdef')], wrapWidth: 50);

      expect(
        boxed.block,
        const ui.Rect.fromLTWH(0, 0, 50, 60),
        reason: 'two letters fit in 50 and three do not: three lines',
      );
    });

    test('hangs from its anchor whatever its alignment — the alignment '
        'places the lines INSIDE the width', () {
      ui.Rect first(TextCelAlign align) {
        final boxed = set([run('abcdef')], wrapWidth: 50, align: align);
        expect(boxed.block, const ui.Rect.fromLTWH(0, 0, 50, 60));
        return boxed.caretRect(const TextPosition(offset: 0));
      }

      expect(first(TextCelAlign.left).left, 0);
      expect(first(TextCelAlign.center).left, 5);
      expect(first(TextCelAlign.right).left, 10);
    });

    test('🚨a text SHORTER than its box is still in a box that wide: its '
        'line stands in the WIDTH as the alignment says, not in its own '
        'length', () {
      // 「ab」 is 40 long, in a box of 100.
      ui.Rect first(TextCelAlign align) {
        final boxed = set([run('ab')], wrapWidth: 100, align: align);
        expect(boxed.block, const ui.Rect.fromLTWH(0, 0, 100, 20));
        return boxed.caretRect(const TextPosition(offset: 0));
      }

      expect(first(TextCelAlign.left).left, 0);
      expect(first(TextCelAlign.center).left, 30);
      expect(first(TextCelAlign.right).left, 60);
    });
  });

  group('runs', () {
    test('each run is set at its own size, and a line is as tall as its '
        'tallest letter', () {
      final mixed = set([run('a'), run('b', size: 40)]);

      expect(mixed.block, const ui.Rect.fromLTWH(0, 0, 60, 40));
    });

    test('🚨a run with NO tracking is not set with the last run\'s — every '
        'value is said out loud', () {
      // The runs are nested in the last one's style, and what a run leaves
      // unsaid the engine fills in from there.
      expect(
        set([run('a'), run('b', tracking: 10)]).block.width,
        20 + 30,
        reason: 'only the second letter is tracked',
      );
      expect(
        set([run('a', tracking: 10), run('b')]).block.width,
        30 + 20,
      );
    });

    test('a line\'s pitch is the text\'s line height times its letters\' '
        'size', () {
      expect(set([run('a\nb')], lineHeight: 1.5).block.height, 60);
      expect(set([run('a\nb')], lineHeight: 0.5).block.height, 20);
    });

    test('🚨an outline on one run changes nothing of another run\'s '
        'pixels — the letter with none is not drawn twice', () async {
      // Half a pixel off the grid, so the plain letter has soft edges: drawn
      // a second time under its own fill they would come out heavier.
      Future<Uint8List> plainLetterOf(List<CelTextSpan> spans) async {
        final bytes = await drawn(set(spans, x: 10.5, y: 10.5), 80, 48);
        // The plain letter's columns, clear of the outlined one beside it.
        return Uint8List.fromList([
          for (var y = 0; y < 48; y += 1)
            for (var x = 0; x < 24; x += 1) ...pixel(bytes, 80, x, y),
        ]);
      }

      final beside = await plainLetterOf([
        run('a'),
        run('b', outline: 0xFFFF0000, outlineWidth: 4),
      ]);
      final alone = await plainLetterOf([run('a'), run('b')]);

      expect(alone.any((byte) => byte != 0), isTrue, reason: '⛔fixture');
      expect(
        alone.any((byte) => byte != 0 && byte != 255),
        isTrue,
        reason: '⛔fixture: the letter has soft edges',
      );
      expect(beside, alone);
    });

    test('the outline is stroked UNDER the letters: half its width shows '
        'outside them, in its own colour', () async {
      final bytes = await drawn(
        set([run('a', outline: 0xFFFF0000, outlineWidth: 4)], x: 10, y: 10),
        48,
        48,
      );

      expect(pixel(bytes, 48, 9, 20), [255, 0, 0, 255], reason: 'outside');
      expect(pixel(bytes, 48, 8, 20), [255, 0, 0, 255]);
      expect(pixel(bytes, 48, 7, 20), [0, 0, 0, 0], reason: 'past the stroke');
      expect(pixel(bytes, 48, 10, 20), [0, 0, 0, 255], reason: 'the letter');
      expect(pixel(bytes, 48, 11, 20), [0, 0, 0, 255]);
    });

    test('🚨a text set to the RIGHT is drawn — letters and outline both — '
        'from where its letters\' own box begins, to the pixel', () async {
      // The engine is handed a pixel of room to align in, and its box of
      // the letters begins that room before the block: drawn from the
      // block's own corner, letters or outline would stand a pixel out.
      // 「a」 at 20 ends on the anchor at 30, so its letter runs from 10.
      final bytes = await drawn(
        set(
          [run('a', outline: 0xFFFF0000, outlineWidth: 4)],
          x: 30,
          y: 10,
          align: TextCelAlign.right,
        ),
        48,
        48,
      );

      expect(pixel(bytes, 48, 7, 20), [0, 0, 0, 0], reason: 'past the stroke');
      expect(pixel(bytes, 48, 8, 20), [255, 0, 0, 255]);
      expect(pixel(bytes, 48, 9, 20), [255, 0, 0, 255]);
      expect(pixel(bytes, 48, 10, 20), [0, 0, 0, 255], reason: 'the letter');
      expect(pixel(bytes, 48, 29, 20), [0, 0, 0, 255], reason: 'the letter');
      expect(pixel(bytes, 48, 30, 20), [255, 0, 0, 255]);
      expect(pixel(bytes, 48, 31, 20), [255, 0, 0, 255]);
      expect(pixel(bytes, 48, 32, 20), [0, 0, 0, 0], reason: 'past the stroke');
    });

    test('the outline turns its corners ROUND', () async {
      final bytes = await drawn(
        set([run('a', outline: 0xFFFF0000, outlineWidth: 4)], x: 10, y: 10),
        48,
        48,
      );

      // The pixel in the stroke's outermost corner: a mitred join fills
      // it, a bevelled one leaves it clear, a round one covers part of it.
      final corner = pixel(bytes, 48, 8, 8)[3];
      expect(corner, greaterThan(0));
      expect(corner, lessThan(255));
    });

    test('an outline colour with NO width draws nothing', () async {
      final bytes = await drawn(
        set([run('a', outline: 0xFFFF0000)], x: 10, y: 10),
        48,
        48,
      );

      expect(pixel(bytes, 48, 9, 20), [0, 0, 0, 0]);
      expect(pixel(bytes, 48, 10, 20), [0, 0, 0, 255]);
    });
  });

  group('a text with no letters', () {
    test('is one line as tall as the letter about to be typed, and no '
        'width', () {
      final empty = set(
        const [],
        x: 7,
        y: 9,
        lineHeight: 1.5,
        nextLetterStyle: const TextLetterStyle(fontSize: 30),
      );

      expect(empty.block, const ui.Rect.fromLTWH(0, 0, 0, 45));
      expect(
        empty.caretRect(const TextPosition(offset: 0)),
        const ui.Rect.fromLTWH(0, 0, 0, 45),
      );
    });

    test('the style of the next letter is not read by a text that has '
        'letters', () {
      expect(
        set(
          [run('ab')],
          nextLetterStyle: const TextLetterStyle(fontSize: 90),
        ).block,
        const ui.Rect.fromLTWH(0, 0, 40, 20),
      );
    });
  });

  group('the caret', () {
    test('stands before the letter it is asked for, as tall as its line', () {
      final text = set([run('ab\nc', size: 20)], lineHeight: 1.5);

      expect(
        text.caretRect(const TextPosition(offset: 1)),
        const ui.Rect.fromLTWH(20, 0, 0, 30),
      );
      expect(
        text.caretRect(const TextPosition(offset: 3)),
        const ui.Rect.fromLTWH(0, 30, 0, 30),
        reason: 'after the break: the second line',
      );
    });

    test('a break at the END of the text opens a line: the block grows by '
        'it and the caret stands on it', () {
      final text = set([run('ab\n')]);

      expect(text.block, const ui.Rect.fromLTWH(0, 0, 40, 40));
      expect(
        text.caretRect(const TextPosition(offset: 3)),
        const ui.Rect.fromLTWH(0, 20, 0, 20),
      );
    });

    test('🚨a line a break opens at the end is measured by the letters of '
        'the LAST run — the run the break is in', () {
      final text = set([run('a'), run('b\n', size: 40)]);

      expect(
        text.caretRect(const TextPosition(offset: 3)),
        const ui.Rect.fromLTWH(0, 40, 0, 40),
      );
    });

    test('is in the text\'s OWN frame: a centred text\'s starts left of '
        'the anchor', () {
      final centred = set(
        [run('ab')],
        x: 300,
        y: 200,
        align: TextCelAlign.center,
      );

      expect(
        centred.caretRect(const TextPosition(offset: 0)),
        const ui.Rect.fromLTWH(-20, 0, 0, 20),
      );
    });
  });

  group('the letters under a press', () {
    test('the place between letters nearest a point of the CANVAS', () {
      final text = set([run('abcd')], x: 100, y: 50);

      expect(text.positionAt(const ui.Offset(100 + 44, 60)).offset, 2);
      expect(text.positionAt(const ui.Offset(100 + 56, 60)).offset, 3);
      expect(text.positionAt(const ui.Offset(100 - 500, 60)).offset, 0);
      expect(text.positionAt(const ui.Offset(100 + 500, 60)).offset, 4);
    });

    test('of a centred text', () {
      final text = set(
        [run('abcd')],
        x: 100,
        y: 50,
        align: TextCelAlign.center,
      );

      // The block runs from 60 to 140.
      expect(text.positionAt(const ui.Offset(60 + 44, 60)).offset, 2);
    });

    test('of a turned text', () {
      final text = set([run('abcd')], x: 100, y: 50, turn: 90);

      // The letters run DOWN from the anchor, and the line is to its left.
      expect(text.positionAt(const ui.Offset(100 - 10, 50 + 44)).offset, 2);
      expect(text.positionAt(const ui.Offset(100 - 10, 50 + 56)).offset, 3);
    });

    test('the boxes of a run of letters, one a line, each as tall as its '
        'line', () {
      final text = set([run('ab\ncd')]);

      final boxes = text
          .selectionRects(1, 4)
          .where((box) => box.width > 0)
          .toList();

      expect(boxes, const [
        ui.Rect.fromLTRB(20, 0, 40, 20),
        ui.Rect.fromLTRB(0, 20, 20, 40),
      ]);
    });

    test('each box is as tall as its LINE, whatever the size of the letters '
        'in it', () {
      final text = set([run('a'), run('b', size: 40)]);

      expect(text.selectionRects(0, 1), const [
        ui.Rect.fromLTRB(0, 0, 20, 40),
      ]);
    });

    test('the boxes are in the text\'s own frame', () {
      final text = set(
        [run('ab')],
        x: 300,
        y: 200,
        turn: 30,
        align: TextCelAlign.right,
      );

      expect(text.selectionRects(0, 1), const [
        ui.Rect.fromLTRB(-40, 0, -20, 20),
      ]);
    });
  });

  group('the turn', () {
    test('a text turns about its anchor, clockwise: a quarter turn runs its '
        'letters down', () {
      final text = set([run('ab')], x: 50, y: 30, turn: 90);

      expect(text.block, const ui.Rect.fromLTWH(0, 0, 40, 20));
      final corners = text.boxCorners;
      expect(corners[0], near(const ui.Offset(50, 30)));
      expect(corners[1], near(const ui.Offset(50, 70)));
      expect(corners[2], near(const ui.Offset(30, 70)));
      expect(corners[3], near(const ui.Offset(30, 30)));
    });

    test('a point goes to the canvas and back', () {
      final text = set([run('ab')], x: 50, y: 30, turn: 37);
      const local = ui.Offset(12.5, -3.25);

      final onCanvas = text.toCanvas(local);

      expect(
        onCanvas,
        near(
          ui.Offset(
            50 +
                12.5 * math.cos(37 * math.pi / 180) +
                3.25 * math.sin(37 * math.pi / 180),
            30 +
                12.5 * math.sin(37 * math.pi / 180) -
                3.25 * math.cos(37 * math.pi / 180),
          ),
        ),
      );
      expect(text.toLocal(onCanvas), near(local));
    });

    test('a text that is not turned is where its numbers say, to the bit', () {
      final text = set([run('ab')], x: 50.5, y: 30.25);

      const local = ui.Offset(1, 2);
      const onCanvas = ui.Offset(51.5, 32.25);
      expect(text.toCanvas(local), onCanvas);
      expect(text.toLocal(onCanvas), local);
    });

    test('a press is on the text when it is inside its TURNED box', () {
      final text = set([run('ab')], x: 50, y: 30, turn: 90);

      expect(text.boxContains(const ui.Offset(40, 50)), isTrue);
      expect(
        text.boxContains(const ui.Offset(60, 40)),
        isFalse,
        reason: 'where the letters would be had it not turned',
      );
    });

    test('the turned text is drawn turned', () async {
      final bytes = await drawn(
        set([run('ab', color: 0xFF0A141E)], x: 50, y: 30, turn: 90),
        80,
        80,
      );

      expect(pixel(bytes, 80, 40, 50), [10, 20, 30, 255]);
      expect(pixel(bytes, 80, 60, 40), [0, 0, 0, 0]);
    });
  });

  group('the box behind the letters', () {
    test('a text with none has a box that is its lines\' block', () {
      final text = set([run('ab')]);

      expect(text.pad, 0);
      expect(text.box, text.block);
    });

    test('reaches a quarter of the LARGEST letter\'s size past the block', () {
      final text = set(
        [run('a'), run('b', size: 40)],
        background: 0xFF00FF00,
      );

      expect(text.pad, 10);
      expect(text.box, const ui.Rect.fromLTRB(-10, -10, 70, 50));
      expect(
        set(
          [run('a', size: 40), run('b')],
          background: 0xFF00FF00,
        ).pad,
        10,
        reason: 'the largest, wherever it stands in the text',
      );
    });

    test('a press on the box behind the letters is a press on the text', () {
      final text = set([run('ab')], x: 50, y: 30, background: 0xFF00FF00);

      // The box reaches 5 past the block.
      expect(text.boxContains(const ui.Offset(47, 28)), isTrue);
      expect(text.boxContains(const ui.Offset(44, 28)), isFalse);
      expect(
        set([run('ab')], x: 50, y: 30).boxContains(const ui.Offset(47, 28)),
        isFalse,
        reason: 'a text with no box behind it ends at its block',
      );
    });

    test('is filled under the letters', () async {
      final bytes = await drawn(
        set(
          [run('a', color: 0xFF0A141E)],
          x: 20,
          y: 20,
          background: 0xFF00FF00,
        ),
        60,
        60,
      );

      expect(pixel(bytes, 60, 16, 16), [0, 255, 0, 255], reason: 'the pad');
      expect(pixel(bytes, 60, 44, 44), [0, 255, 0, 255]);
      expect(pixel(bytes, 60, 14, 30), [0, 0, 0, 0], reason: 'past the box');
      expect(pixel(bytes, 60, 30, 30), [10, 20, 30, 255], reason: 'the letter');
    });
  });

  group('where its pixels can be', () {
    test('whole pixels around the block, a letter\'s size of room on every '
        'side', () {
      // The room is 20. Each edge falls nearer the pixel INSIDE it in one of
      // the two, where rounding to the nearest would cut the edge off.
      expect(
        set([run('ab')], x: 10.75, y: 10.25).inkBounds,
        const ui.Rect.fromLTRB(-10, -10, 71, 51),
        reason: 'the block is (10.75, 10.25)–(50.75, 30.25)',
      );
      expect(
        set([run('ab')], x: 10.25, y: 10.75).inkBounds,
        const ui.Rect.fromLTRB(-10, -10, 71, 51),
        reason: 'the block is (10.25, 10.75)–(50.25, 30.75)',
      );
    });

    test('and half the widest outline, and the box behind the letters', () {
      expect(
        set([
          run('a', outline: 0xFFFF0000, outlineWidth: 6),
          run('b', outline: 0xFFFF0000, outlineWidth: 2),
        ]).inkBounds,
        const ui.Rect.fromLTRB(-23, -23, 63, 43),
      );
      expect(
        set([run('ab')], background: 0xFF00FF00).inkBounds,
        const ui.Rect.fromLTRB(-25, -25, 65, 45),
      );
      expect(
        set([
          run('ab', outlineWidth: 6),
        ]).inkBounds,
        const ui.Rect.fromLTRB(-20, -20, 60, 40),
        reason: 'a width with no colour is no outline',
      );
    });

    test('follows the turn', () {
      final text = set([run('ab')], x: 50, y: 30, turn: 90);

      // The box is (30, 30)–(50, 70) on the canvas; the room is 20.
      expect(text.inkBounds, const ui.Rect.fromLTRB(10, 10, 70, 90));
    });
  });

  group('a text\'s box on the canvas', () {
    test('is the layout\'s own box as a value: its corners, its middle and '
        'what is inside it — turned as the text is', () {
      // 「ab」 is 40 by 20, the box behind it 5 further out on every side:
      // from (-5, -5) to (45, 25) in the text's own frame, its middle at
      // (20, 10). A quarter turn about the anchor takes (x, y) to (-y, x).
      final layout = set(
        [run('ab')],
        x: 30,
        y: 10,
        turn: 90,
        background: 0xFFFFFFFF,
      );
      final box = layout.onCanvas;

      expect(box.corners, layout.boxCorners);
      expect(box.centre.dx, closeTo(20, 1e-9));
      expect(box.centre.dy, closeTo(30, 1e-9));
      // Along the text's own line, which runs DOWN the canvas now: 44 from
      // the anchor is inside the box, 46 is past its end.
      expect(box.contains(const ui.Offset(30, 54)), isTrue);
      expect(box.contains(const ui.Offset(30, 56)), isFalse);
      expect(layout.boxContains(const ui.Offset(30, 54)), isTrue);
      expect(layout.boxContains(const ui.Offset(30, 56)), isFalse);
    });

    test('🚨is kept WITH the content: asked for again it is the same box, '
        'and it is the box the content has when its letters are set', () {
      final content = CelTextContent(
        spans: [run('ab')],
        anchor: CanvasPoint(x: 30, y: 10),
        rotationDegrees: 90,
        backgroundColor: 0xFFFFFFFF,
      );

      final box = celTextBoxOf(content);

      expect(identical(celTextBoxOf(content), box), isTrue);
      final layout = layoutCelText(content);
      addTearDown(layout.dispose);
      expect(box.corners, layout.boxCorners);
      expect(box.centre, layout.onCanvas.centre);
      expect(box.contains(const ui.Offset(30, 54)), isTrue);
      expect(box.contains(const ui.Offset(30, 56)), isFalse);
    });
  });

  group('the app\'s faces', () {
    test('a run with no chosen face is set in the app\'s, and a bold run in '
        'its bold', () async {
      await loadTheAppFaces();

      final plain = set([run('illicit')]);
      final bold = set([run('illicit', bold: true)]);

      expect(
        plain.block.width,
        lessThan(7 * 20),
        reason: 'the test font sets every letter a whole size wide',
      );
      expect(bold.block.width, isNot(plain.block.width));
      final other = set([run('illicit', family: 'Nanum Gothic')]);
      expect(
        other.block.width,
        isNot(plain.block.width),
        reason: 'a run in a chosen face is set in THAT face',
      );
      expect(other.block.width, lessThan(7 * 20));
      // ↩️This asked for 「FlutterTest」, the test engine's own font, and
      // got it. A family this device does not hold is set in the app's own
      // now (`CanvasLetterFaces`, the text tool's faces) — not in whatever
      // the engine would make of its name.
      expect(
        set([run('illicit', family: 'FlutterTest')]).block.width,
        plain.block.width,
      );
    });
  });
}
