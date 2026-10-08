import 'dart:math' as math;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/cel_text_box_edits.dart';
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
    });

    test('what is not a length stays: the letters, the colours, the '
        'alignment, the line pitch, the turn', () {
      final before = said(turn: 30);

      final scaled = celTextScaledAbout(before, 2, CanvasPoint(x: 0, y: 0));

      expect(scaled.text, 'abc');
      expect(scaled.spans[0].style.outlineColor, 0xFFFF0000);
      expect(scaled.align, TextCelAlign.right);
      expect(scaled.lineHeight, 1.5);
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
