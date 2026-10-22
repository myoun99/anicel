import 'dart:math' as math;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/cel_text_box_edits.dart';
import 'package:anicel/src/services/cel_text_frame.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool): what a hand on a text's box does to it — its
/// corner scales the letters themselves, outside it turns the text, its
/// side edge sets a box's width — each about the box's CENTRE, the one law
/// every box on the canvas keeps (F-222), while the text itself turns about
/// its anchor.
void main() {
  CelTextContent said({
    double x = 100,
    double y = 50,
    double? wrapWidth,
    double turn = 0,
    bool vertical = false,
  }) => CelTextContent(
    spans: const [
      CelTextSpan(
        text: 'ab',
        style: TextLetterStyle(
          fontSize: 20,
          letterSpacing: 2,
          outlineColor: 0xFFFF0000,
          outlineWidth: 4,
        ),
      ),
      CelTextSpan(text: 'c', style: TextLetterStyle(fontSize: 40)),
    ],
    anchor: CanvasPoint(x: x, y: y),
    wrapWidth: wrapWidth,
    rotationDegrees: turn,
    align: TextCelAlign.right,
    lineHeight: 1.5,
    backgroundColor: 0xFF00FF00,
    vertical: vertical,
  );

  Matcher near(double x, double y) => isA<CanvasPoint>()
      .having((p) => p.x, 'x', closeTo(x, 1e-9))
      .having((p) => p.y, 'y', closeTo(y, 1e-9));

  group('a corner — the scale', () {
    test('every LENGTH of the text is scaled: the letters\' size, tracking '
        'and outline, and a box\'s width', () {
      final scaled = celTextScaledAbout(
        said(wrapWidth: 120),
        1.5,
        CanvasPoint(x: 100, y: 50),
      );

      expect(scaled.spans[0].style.fontSize, 30);
      expect(scaled.spans[0].style.letterSpacing, 3);
      expect(scaled.spans[0].style.outlineWidth, 6);
      expect(scaled.spans[1].style.fontSize, 60);
      expect(scaled.wrapWidth, 180);
      expect(
        celTextScaledAbout(
          said(wrapWidth: 120).copyWith(minHeight: 80),
          1.5,
          CanvasPoint(x: 100, y: 50),
        ).minHeight,
        120,
        reason: 'how tall it is at least (F-317)',
      );
      expect(scaled.minHeight, isNull, reason: 'it had none');
    });

    test('what is not a length stays: the letters, the colours, the '
        'alignment, the line pitch, the turn', () {
      final before = said(turn: 30);

      final scaled = celTextScaledAbout(before, 2, CanvasPoint(x: 0, y: 0));

      expect(scaled.text, 'abc');
      expect(scaled.spans[0].style.outlineColor, 0xFFFF0000);
      expect(
        scaled.paragraphs.single,
        const CelTextParagraph(align: TextCelAlign.right, lineHeight: 1.5),
      );
      expect(scaled.rotationDegrees, 30);
      expect(scaled.backgroundColor, 0xFF00FF00);
      expect(scaled.wrapWidth, isNull, reason: 'a text that grows has none');
    });

    test('🚨about the CENTRE: the anchor goes where the centre standing '
        'still puts it', () {
      final scaled = celTextScaledAbout(
        said(x: 100, y: 50),
        2,
        CanvasPoint(x: 160, y: 80),
      );

      // The anchor was (−60, −30) from the centre; it is twice that now.
      expect(scaled.anchor, near(40, 20));
      expect(
        celTextScaledAbout(
          said(x: 100, y: 50),
          0.5,
          CanvasPoint(x: 160, y: 80),
        ).anchor,
        near(130, 65),
      );
    });

    test('stops where the smallest letter would go under one pixel', () {
      final scaled = celTextScaledAbout(
        said(wrapWidth: 120),
        0.001,
        CanvasPoint(x: 100, y: 50),
      );

      // The smallest letter is 20: the scale stops at a twentieth.
      expect(scaled.spans[0].style.fontSize, celTextMinFontSize);
      expect(scaled.spans[1].style.fontSize, 2);
      expect(scaled.wrapWidth, 6);
      expect(
        celTextScaledAbout(
          said(wrapWidth: 120).copyWith(minHeight: 10),
          0.001,
          CanvasPoint(x: 100, y: 50),
        ).minHeight,
        celTextMinWrapWidth,
        reason: 'a twentieth of 10 is under a pixel',
      );
    });
  });

  group('outside the box — the turn', () {
    test('the text turns further by what the hand turned', () {
      final turned = celTextTurnedAbout(
        said(turn: 30),
        45,
        CanvasPoint(x: 100, y: 50),
      );

      expect(turned.rotationDegrees, 75);
      expect(
        celTextTurnedAbout(
          said(turn: 30),
          -45,
          CanvasPoint(x: 100, y: 50),
        ).rotationDegrees,
        -15,
      );
    });

    test('🚨about the CENTRE, clockwise: the anchor swings round it', () {
      final turned = celTextTurnedAbout(
        said(x: 100, y: 50),
        90,
        CanvasPoint(x: 160, y: 80),
      );

      // (−60, −30) from the centre, a quarter turn clockwise: (30, −60).
      expect(turned.anchor, near(190, 20));
    });

    test('a turn about the anchor itself leaves it where it is', () {
      final turned = celTextTurnedAbout(
        said(x: 100, y: 50),
        37,
        CanvasPoint(x: 100, y: 50),
      );

      expect(turned.anchor, near(100, 50));
      expect(turned.rotationDegrees, 37);
    });

    test('nothing else changes', () {
      final before = said(wrapWidth: 120);

      final turned = celTextTurnedAbout(before, 10, CanvasPoint(x: 0, y: 0));

      expect(turned.spans, before.spans);
      expect(turned.wrapWidth, 120);
    });
  });

  group('⑦ the lean and the mirror', () {
    /// Where [point] falls on [content], in its own frame.
    Offset onText(CelTextContent content, CanvasPoint point) =>
        CelTextFrame.of(content).toLocal(Offset(point.x, point.y));

    test('🚨each goes about the point it is given, which stays where it '
        'was — the turn\'s law', () {
      final before = said(turn: 30);
      final still = CanvasPoint(x: 140, y: 70);

      for (final (name, after) in [
        ('leaned', celTextLeanedAbout(before, 25, still)),
        ('mirrored', celTextFlippedAbout(before, still, flipped: true)),
      ]) {
        final at = CelTextFrame.of(after).toCanvas(onText(before, still));
        expect(at.dx, closeTo(140, 1e-9), reason: name);
        expect(at.dy, closeTo(70, 1e-9), reason: name);
        expect(after.rotationDegrees, 30, reason: '$name, still turned');
      }
    });

    test('a lean is set, not added, and a mirror twice is none', () {
      final still = CanvasPoint(x: 140, y: 70);
      final leaned = celTextLeanedAbout(said(), 25, still);

      expect(celTextLeanedAbout(leaned, 10, still).skewDegrees, 10);
      final back = celTextFlippedAbout(
        celTextFlippedAbout(leaned, still, flipped: true),
        still,
        flipped: false,
      );
      expect(back.flipped, isFalse);
      expect(back.anchor, near(leaned.anchor.x, leaned.anchor.y));
    });

    test('🚨a hand\'s travel is read in the text\'s own frame: straight down '
        'a leaned box\'s side it is all stacking, and along a mirrored '
        'text\'s lines it runs them backwards', () {
      final leaned = said(wrapWidth: 120).copyWith(skewDegrees: 30);
      final down = CelTextFrame.of(leaned).onCanvas(const Offset(0, 10));

      final travel = celTextTravelAlong(leaned, down);
      expect(travel.letters, closeTo(0, 1e-9));
      expect(travel.stacking, closeTo(10, 1e-9));

      final mirrored = said(wrapWidth: 120).copyWith(flipped: true);
      expect(
        celTextTravelAlong(mirrored, const Offset(10, 0)).letters,
        closeTo(-10, 1e-9),
      );
    });
  });

  group('a side edge — a box\'s width', () {
    test('the RIGHT edge sets the width and the box stays hung where it '
        'was', () {
      final widened = celTextBoxWidened(
        said(wrapWidth: 120),
        200,
        byLeadingEdge: false,
      );

      expect(widened.wrapWidth, 200);
      expect(widened.anchor, near(100, 50));
    });

    test('🚨the LEFT edge carries the anchor, so the right edge stays where '
        'it was', () {
      final narrowed = celTextBoxWidened(
        said(wrapWidth: 120),
        80,
        byLeadingEdge: true,
      );

      expect(narrowed.wrapWidth, 80);
      expect(narrowed.anchor, near(140, 50));
      expect(
        celTextBoxWidened(said(wrapWidth: 120), 150, byLeadingEdge: true).anchor,
        near(70, 50),
      );
    });

    test('along the text\'s OWN line, when it is turned', () {
      final narrowed = celTextBoxWidened(
        said(wrapWidth: 120, turn: 90),
        80,
        byLeadingEdge: true,
      );

      // The line runs DOWN: the anchor moves 40 down it.
      expect(narrowed.anchor, near(100, 90));

      final slanted = celTextBoxWidened(
        said(wrapWidth: 120, turn: 30),
        80,
        byLeadingEdge: true,
      );
      expect(
        slanted.anchor,
        near(
          100 + 40 * math.cos(30 * math.pi / 180),
          50 + 40 * math.sin(30 * math.pi / 180),
        ),
      );
    });

    test('a box is never narrower than a pixel', () {
      final box = said(wrapWidth: 120);

      expect(
        celTextBoxWidened(box, -30, byLeadingEdge: false).wrapWidth,
        celTextMinWrapWidth,
      );
      expect(
        celTextBoxWidened(box, -30, byLeadingEdge: true).anchor,
        near(100 + 119, 50),
        reason: 'the anchor stops with the width',
      );
    });

    test('a text that grows has no width to drag', () {
      expect(
        () => celTextBoxWidened(said(), 100, byLeadingEdge: false),
        throwsArgumentError,
      );
    });
  });

  // F-317 (유저 2026-10-08): 「위아래 사각형도 존재하는게 좋을듯」 — and
  // F-317-Q2: 「끈 높이는 최소치, 넘치면 상자가 늘어난다」. Its lines here
  // are 60 deep, whatever they are set in: the layout's to say.
  group('a top or bottom edge — how tall a box is at least', () {
    test('the BOTTOM edge sets it and the box stays hung where it was', () {
      final deepened = celTextBoxDeepened(
        said(wrapWidth: 120),
        90,
        lettersDepth: 60,
        byLeadingEdge: false,
      );

      expect(deepened.minHeight, 90);
      expect(deepened.wrapWidth, 120);
      expect(deepened.anchor, near(100, 50));
    });

    test('🚨the TOP edge carries the anchor the way the lines stack, so the '
        'bottom stays where it was — from its lines, or from how tall it '
        'was at least', () {
      expect(
        celTextBoxDeepened(
          said(wrapWidth: 120),
          90,
          lettersDepth: 60,
          byLeadingEdge: true,
        ).anchor,
        near(100, 20),
      );
      final tall = said(wrapWidth: 120).copyWith(minHeight: 90);
      final shortened = celTextBoxDeepened(
        tall,
        70,
        lettersDepth: 60,
        byLeadingEdge: true,
      );
      expect(shortened.minHeight, 70);
      expect(shortened.anchor, near(100, 70));
      // At least 30, and its lines 60 deep: its bottom is theirs.
      expect(
        celTextBoxDeepened(
          said(wrapWidth: 120).copyWith(minHeight: 30),
          90,
          lettersDepth: 60,
          byLeadingEdge: true,
        ).anchor,
        near(100, 20),
      );
    });

    test('🚨a box is never less than its lines: an edge taken into them '
        'stops at them, and the top carries the anchor no further', () {
      final tall = said(wrapWidth: 120).copyWith(minHeight: 90);

      expect(
        celTextBoxDeepened(
          tall,
          10,
          lettersDepth: 60,
          byLeadingEdge: false,
        ).minHeight,
        60,
      );
      final stopped = celTextBoxDeepened(
        tall,
        10,
        lettersDepth: 60,
        byLeadingEdge: true,
      );
      expect(stopped.minHeight, 60);
      expect(stopped.anchor, near(100, 80));
      expect(
        celTextBoxDeepened(
          said(wrapWidth: 120),
          -5,
          lettersDepth: 0,
          byLeadingEdge: false,
        ).minHeight,
        celTextMinWrapWidth,
        reason: 'nor less than a pixel',
      );
    });

    test('across the text\'s OWN lines when it is turned, and in COLUMNS '
        'leftwards: the edge the anchor is on is then the right one', () {
      // A quarter turn: the lines stack LEFTWARDS on the canvas, so the top
      // edge is on its right.
      expect(
        celTextBoxDeepened(
          said(wrapWidth: 120, turn: 90),
          90,
          lettersDepth: 60,
          byLeadingEdge: true,
        ).anchor,
        near(130, 50),
      );
      expect(
        celTextBoxDeepened(
          said(wrapWidth: 120, vertical: true),
          90,
          lettersDepth: 60,
          byLeadingEdge: true,
        ).anchor,
        near(130, 50),
      );
      expect(
        celTextBoxDeepened(
          said(wrapWidth: 120, vertical: true),
          90,
          lettersDepth: 60,
          byLeadingEdge: false,
        ).anchor,
        near(100, 50),
      );
    });

    test('a text that grows has no box to deepen', () {
      expect(
        () => celTextBoxDeepened(
          said(),
          100,
          lettersDepth: 60,
          byLeadingEdge: false,
        ),
        throwsArgumentError,
      );
    });
  });

  // 세로쓰기 (유저 2026-10-06): a box's room is along its letters' way, and
  // in columns that is DOWN.
  group('the way the letters run', () {
    Matcher way(double dx, double dy) => isA<({double dx, double dy})>()
        .having((w) => w.dx, 'dx', closeTo(dx, 1e-9))
        .having((w) => w.dy, 'dy', closeTo(dy, 1e-9));

    test('along the lines; in columns, down them — turned as the text is', () {
      expect(celTextLettersWay(said()), way(1, 0));
      expect(celTextLettersWay(said(turn: 90)), way(0, 1));
      expect(celTextLettersWay(said(vertical: true)), way(0, 1));
      expect(celTextLettersWay(said(vertical: true, turn: 90)), way(-1, 0));
    });

    test('and the lines STACK a quarter turn clockwise from it: down them; '
        'in columns, leftwards — turned as the text is', () {
      expect(celTextStackingWay(said()), way(0, 1));
      expect(celTextStackingWay(said(turn: 90)), way(-1, 0));
      expect(celTextStackingWay(said(vertical: true)), way(-1, 0));
      expect(celTextStackingWay(said(vertical: true, turn: 90)), way(0, -1));
      expect(
        celTextStackingWay(said(turn: 30)),
        way(-math.sin(30 * math.pi / 180), math.cos(30 * math.pi / 180)),
      );
    });

    test('🚨in COLUMNS the edge the anchor is on is the TOP one: it carries '
        'the anchor DOWN the column, so the foot stays where it was', () {
      final shortened = celTextBoxWidened(
        said(wrapWidth: 120, vertical: true),
        80,
        byLeadingEdge: true,
      );

      expect(shortened.wrapWidth, 80);
      expect(shortened.anchor, near(100, 90));
    });

    test('the foot of a column only changes how long it is', () {
      final lengthened = celTextBoxWidened(
        said(wrapWidth: 120, vertical: true),
        200,
        byLeadingEdge: false,
      );

      expect(lengthened.wrapWidth, 200);
      expect(lengthened.anchor, near(100, 50));
    });

    test('down the text\'s OWN column, when it is turned', () {
      // A quarter turn: down the column is to the LEFT on the canvas.
      expect(
        celTextBoxWidened(
          said(wrapWidth: 120, vertical: true, turn: 90),
          80,
          byLeadingEdge: true,
        ).anchor,
        near(60, 50),
      );
    });
  });
}
