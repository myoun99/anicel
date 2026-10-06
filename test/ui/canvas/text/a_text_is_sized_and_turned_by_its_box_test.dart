import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';

/// 🚨★★★A TEXT HELD BY ITS BOX (R9-rest) — the real app, a real mouse.
///
/// The press table 유저 took on 2026-10-06, the half of it for a text in
/// hand by its box: a corner SCALES it (「글자가 커진다, 중심 기준」), a drag
/// outside TURNS it, the side edge of a box sets its WIDTH — the one order
/// every box on the canvas keeps (F-222) — and each is one step of history,
/// the text still in hand when the hand comes up.
///
/// In the test font 「hi」 at the tool's own size is 96 wide on a line 60
/// tall: its box stands from the pixel in view `c` to `c + (96, 60)`, its
/// centre at `c + (48, 30)`.
void main() {
  const black = [0, 0, 0, 255];

  /// 「hi」 on the cel at the pixel in view, in hand by its box.
  Future<Offset> hiInHandByItsBox(WidgetTester tester) async {
    await pumpTextToolApp(tester);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(textToolOf(tester).hold, CelTextHold.box, reason: '⛔fixture');
    expect(celOf(tester).texts, hasLength(1), reason: '⛔fixture');
    return c;
  }

  /// A box 220 wide holding 「hi」 at the pixel in view, in hand by its box.
  Future<Offset> boxInHand(WidgetTester tester) async {
    await pumpTextToolApp(tester);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await dragFrom(tester, c, Offset(c.dx + 220, c.dy + 190));
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(
      celOf(tester).texts.single.content.wrapWidth,
      220,
      reason: '⛔fixture',
    );
    return c;
  }

  testWidgets('🚨a CORNER scales the letters themselves, about the box\'s '
      'centre — one step, the text still in hand', (tester) async {
    final c = await hiInHandByItsBox(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    // The corner taken twice as far from the centre: everything doubles.
    await dragFrom(
      tester,
      Offset(c.dx + 96, c.dy + 60),
      Offset(c.dx + 144, c.dy + 90),
    );

    final scaled = celOf(tester).texts.single.content;
    expect(scaled.spans.single.style.fontSize, closeTo(96, 1e-6));
    expect(scaled.anchor.x, closeTo(c.dx - 48, 1e-6));
    expect(scaled.anchor.y, closeTo(c.dy - 30, 1e-6));
    expect(history.undoCount, steps + 1);
    expect(textToolOf(tester).session, isNotNull, reason: 'in hand');
    final x = c.dx.toInt();
    final y = c.dy.toInt();
    expect(
      shownPixel(celOf(tester), x + 130, y + 80),
      black,
      reason: 'where only the larger letters reach',
    );
    expect(shownPixel(celOf(tester), x - 40, y - 20), black);

    history.undo();
    await pumpFrames(tester);

    final back = celOf(tester).texts.single.content;
    expect(back.spans.single.style.fontSize, 48);
    expect(back.anchor, CanvasPoint(x: c.dx, y: c.dy));
  });

  testWidgets('a drag OUTSIDE the box turns the text about the box\'s '
      'centre — one step, the text still in hand', (tester) async {
    final c = await hiInHandByItsBox(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    // From due right of the centre to due below it: a quarter turn, the
    // way a clock's hand goes.
    await dragFrom(
      tester,
      Offset(c.dx + 248, c.dy + 30),
      Offset(c.dx + 48, c.dy + 230),
    );

    final turned = celOf(tester).texts.single.content;
    expect(turned.rotationDegrees, closeTo(90, 1e-6));
    // The anchor stood (−48, −30) from the centre; it stands (30, −48) now.
    expect(turned.anchor.x, closeTo(c.dx + 78, 1e-6));
    expect(turned.anchor.y, closeTo(c.dy - 18, 1e-6));
    expect(history.undoCount, steps + 1);
    expect(textToolOf(tester).session, isNotNull, reason: 'in hand');

    history.undo();
    await pumpFrames(tester);

    expect(celOf(tester).texts.single.content.rotationDegrees, 0);
  });

  group('a press that goes away', () {
    testWidgets('mid-drag, it sets the text back as it stood: nothing '
        'lands, and the text is still in hand', (tester) async {
      final c = await hiInHandByItsBox(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final before = celOf(tester);

      final mouse = await pressAt(tester, c.dx + 96, c.dy + 60);
      await mouse.moveTo(onScreen(tester, c.dx + 144, c.dy + 90));
      await pumpFrames(tester);
      final tool = textToolOf(tester);
      expect(
        tool.session!.shown.content.spans.single.style.fontSize,
        closeTo(96, 1e-6),
        reason: '⛔fixture: it was following the hand',
      );

      await mouse.cancel();
      await pumpFrames(tester);

      expect(celOf(tester), same(before));
      expect(history.undoCount, steps);
      expect(tool.session, isNotNull, reason: 'in hand');
      expect(tool.session!.shown.content.spans.single.style.fontSize, 48);
    });

    testWidgets('🚨a SECOND FINGER takes a finger\'s drag back — the pair is '
        'the view\'s — and nothing lands when they lift', (tester) async {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.draw,
      );
      addTearDown(() => AppInput.settings.value = const AppInputSettings());
      final c = await hiInHandByItsBox(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final before = celOf(tester);
      final tool = textToolOf(tester);

      // Inside the box, off the cross in its middle.
      final first = await tester.startGesture(
        onScreen(tester, c.dx + 20, c.dy + 12),
        kind: PointerDeviceKind.touch,
        pointer: 7,
      );
      await tester.pump();
      await first.moveTo(onScreen(tester, c.dx + 120, c.dy + 112));
      await tester.pump();
      expect(
        tool.session!.shown.content.anchor,
        CanvasPoint(x: c.dx + 100, y: c.dy + 100),
        reason: '⛔fixture: the finger was moving it',
      );

      final second = await tester.startGesture(
        onScreen(tester, c.dx + 300, c.dy + 30),
        kind: PointerDeviceKind.touch,
        pointer: 8,
      );
      await tester.pump();

      expect(tool.session!.shown.content.anchor, CanvasPoint(x: c.dx, y: c.dy));

      await first.up();
      await second.up();
      await pumpFrames(tester);

      expect(celOf(tester), same(before));
      expect(history.undoCount, steps);
    });
  });

  group('a box — a text of a set width', () {
    testWidgets('its RIGHT edge sets the width in whole pixels, along the '
        'text\'s own line, and the box stays hung where it was', (
      tester,
    ) async {
      final c = await boxInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;

      await dragFrom(
        tester,
        Offset(c.dx + 220, c.dy + 30),
        Offset(c.dx + 300.4, c.dy + 75),
      );

      final widened = celOf(tester).texts.single.content;
      expect(widened.wrapWidth, 300);
      expect(widened.anchor, CanvasPoint(x: c.dx, y: c.dy));
      expect(history.undoCount, steps + 1);
      expect(textToolOf(tester).session, isNotNull, reason: 'in hand');
    });

    testWidgets('🚨its LEFT edge carries the anchor: the right edge stays '
        'where it was', (tester) async {
      final c = await boxInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;

      await dragFrom(
        tester,
        Offset(c.dx, c.dy + 30),
        Offset(c.dx + 40, c.dy + 30),
      );

      final narrowed = celOf(tester).texts.single.content;
      expect(narrowed.wrapWidth, 180);
      expect(narrowed.anchor, CanvasPoint(x: c.dx + 40, y: c.dy));
      expect(history.undoCount, steps + 1);

      history.undo();
      await pumpFrames(tester);

      final back = celOf(tester).texts.single.content;
      expect(back.wrapWidth, 220);
      expect(back.anchor, CanvasPoint(x: c.dx, y: c.dy));
    });
  });

  /// Where the chrome draws the cross now, on the layer: the middle of its
  /// four arms, each fourteen long — which have to agree.
  ///
  /// ⚠️To a millionth of a pixel: a turn is made of sines, and a carry of a
  /// press taken back through the view.
  Offset crossDrawn(WidgetTester tester) {
    final arms = <(Offset, Offset)>[];
    expect(
      tester.renderObject(textChrome()),
      paints..something((method, arguments) {
        if (method == #drawLine) {
          arms.add((arguments[0] as Offset, arguments[1] as Offset));
        }
        return arms.length == 4;
      }),
    );
    final middle = (arms.first.$1 + arms.first.$2) / 2;
    for (final (from, to) in arms) {
      expect(((from + to) / 2 - middle).distance, lessThan(1e-6));
      expect((to - from).distance, closeTo(14, 1e-6));
    }
    return middle;
  }

  // 🗣️유저 2026-10-07 (R9-rest-Q2 「끌어서 중심을 옮긴다」): 「앵커포인트? 랑
  // 같은 개념인거같은데 최대한 같은 법 쓰면서」 — the anchor point's law,
  // 유저's of 2026-09-20: it is in the middle until a hand drags it, the
  // turn goes round it, and 확대/축소 is 「항상 상자의 중심」.
  group('its cross', () {
    /// 「hi」 in hand by its box, its cross carried from the middle of the
    /// box to `c + (8, 40)` — forty back along the line and ten down.
    Future<Offset> crossCarried(WidgetTester tester) async {
      final c = await hiInHandByItsBox(tester);
      await dragFrom(
        tester,
        Offset(c.dx + 48, c.dy + 30),
        Offset(c.dx + 8, c.dy + 40),
      );
      return c;
    }

    testWidgets('🚨a drag ON the cross carries it — it is drawn where the '
        'hand left it — and no letter moves, nothing lands, the text stays '
        'in hand', (tester) async {
      final c = await hiInHandByItsBox(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final before = celOf(tester);
      expect(
        (crossDrawn(tester) - onLayer(tester, c.dx + 48, c.dy + 30)).distance,
        lessThan(1e-6),
        reason: '⛔fixture: in the middle',
      );

      await dragFrom(
        tester,
        Offset(c.dx + 48, c.dy + 30),
        Offset(c.dx + 8, c.dy + 40),
      );

      expect(
        (crossDrawn(tester) - onLayer(tester, c.dx + 8, c.dy + 40)).distance,
        lessThan(1e-6),
      );
      expect(celOf(tester), same(before));
      expect(history.undoCount, steps);
      final tool = textToolOf(tester);
      expect(tool.session, isNotNull, reason: 'in hand');
      expect(tool.hold, CelTextHold.box);
      expect(tool.session!.shown.content.anchor, CanvasPoint(x: c.dx, y: c.dy));
    });

    testWidgets('🚨the TURN goes round the cross where it was carried: the '
        'cross stands, the text goes round it — one step', (tester) async {
      final c = await crossCarried(tester);
      final cross = onLayer(tester, c.dx + 8, c.dy + 40);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;

      // From due right of the cross to due below it: a quarter turn.
      await dragFrom(
        tester,
        Offset(c.dx + 188, c.dy + 40),
        Offset(c.dx + 8, c.dy + 220),
      );

      final turned = celOf(tester).texts.single.content;
      expect(turned.rotationDegrees, closeTo(90, 1e-6));
      // The anchor stood (−8, −40) from the cross; it stands (40, −8) now —
      // about the middle of the box it would be at `c + (78, −18)`.
      expect(turned.anchor.x, closeTo(c.dx + 48, 1e-6));
      expect(turned.anchor.y, closeTo(c.dy + 32, 1e-6));
      expect((crossDrawn(tester) - cross).distance, lessThan(1e-6));
      expect(history.undoCount, steps + 1);
      expect(textToolOf(tester).session, isNotNull, reason: 'in hand');
    });

    testWidgets('🚨a CORNER still sizes the text about the middle of its '
        'BOX, and the cross stands where it was', (tester) async {
      final c = await crossCarried(tester);
      final cross = onLayer(tester, c.dx + 8, c.dy + 40);

      // The corner taken twice as far from the middle of the box.
      await dragFrom(
        tester,
        Offset(c.dx + 96, c.dy + 60),
        Offset(c.dx + 144, c.dy + 90),
      );

      final scaled = celOf(tester).texts.single.content;
      expect(scaled.spans.single.style.fontSize, closeTo(96, 1e-6));
      expect(scaled.anchor.x, closeTo(c.dx - 48, 1e-6));
      expect(scaled.anchor.y, closeTo(c.dy - 30, 1e-6));
      expect((crossDrawn(tester) - cross).distance, lessThan(1e-6));
    });

    testWidgets('a click on the cross is the cross\'s — the letters under '
        'it stay shut — and beside it, the box\'s', (tester) async {
      final c = await hiInHandByItsBox(tester);

      await clickAt(tester, c.dx + 48, c.dy + 30);

      final tool = textToolOf(tester);
      expect(tool.letters, isNull);
      expect(tool.session, isNotNull, reason: 'in hand');

      await clickAt(tester, c.dx + 20, c.dy + 12);

      expect(tool.letters, isNotNull);
    });

    testWidgets('🚨the cross is the HOLD\'S: let go of and taken again, the '
        'text has it in the middle', (tester) async {
      final c = await crossCarried(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(textToolOf(tester).session, isNull, reason: '⛔fixture');

      await clickAt(tester, c.dx + 20, c.dy + 12);

      expect(textToolOf(tester).hold, CelTextHold.box, reason: '⛔fixture');
      expect(textToolOf(tester).session, isNotNull, reason: '⛔fixture');
      expect(
        (crossDrawn(tester) - onLayer(tester, c.dx + 48, c.dy + 30)).distance,
        lessThan(1e-6),
      );
    });
  });

  // The three boxes of the drawing 유저 took on 2026-10-06: dashed on a text
  // nobody is holding; the host's colour, handles and a cross at the centre
  // on one held by its box; the box and the caret on one held by its
  // letters.
  group('the box it wears', () {
    /// The cross at [centre], a point of the layer: two arms seven long,
    /// each white and then in the box's colour.
    PaintPattern crossAt(Offset centre) {
      const across = Offset(7, 0);
      const down = Offset(0, 7);
      return paints
        ..line(p1: centre - across, p2: centre + across, color: Colors.white)
        ..line(p1: centre - down, p2: centre + down, color: Colors.white)
        ..line(
          p1: centre - across,
          p2: centre + across,
          color: AppColors.accent,
        )
        ..line(p1: centre - down, p2: centre + down, color: AppColors.accent);
    }

    // A handle is its square, filled and then stroked: two rects.
    testWidgets('🚨held by its BOX: the box, a handle on each corner, and '
        'the cross at the centre it is turned and sized about', (
      tester,
    ) async {
      final c = await hiInHandByItsBox(tester);

      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 4 * 2));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 4));
      expect(chrome, crossAt(onLayer(tester, c.dx + 48, c.dy + 30)));
    });

    testWidgets('a box: a handle on each side edge too — what is drawn is '
        'what is grabbed', (tester) async {
      await boxInHand(tester);

      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 6 * 2));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 4));
    });

    testWidgets('the cross is where the text is TURNED about: a turn leaves '
        'it standing', (tester) async {
      final c = await hiInHandByItsBox(tester);
      final centre = onLayer(tester, c.dx + 48, c.dy + 30);

      await dragFrom(
        tester,
        Offset(c.dx + 248, c.dy + 30),
        Offset(c.dx + 48, c.dy + 230),
      );
      expect(
        celOf(tester).texts.single.content.rotationDegrees,
        closeTo(90, 1e-6),
        reason: '⛔fixture',
      );

      expect((crossDrawn(tester) - centre).distance, lessThan(1e-6));
    });

    testWidgets('🚨held by its LETTERS: the box and the caret — no handle '
        'and no cross', (tester) async {
      final c = await hiInHandByItsBox(tester);

      // A click inside the box, off the cross in its middle: the letters
      // open.
      await clickAt(tester, c.dx + 20, c.dy + 12);
      expect(textToolOf(tester).letters, isNotNull, reason: '⛔fixture');

      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 0));
      // The caret, and nothing else that is a line.
      expect(chrome, paintsExactlyCountTimes(#drawLine, 1));
    });

    testWidgets('🚨in NOBODY\'S hand: the text wears a dashed box — white '
        'along its whole edge, grey dashes over that — and nothing else', (
      tester,
    ) async {
      final c = await hiInHandByItsBox(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(textToolOf(tester).session, isNull, reason: '⛔fixture');

      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 2));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 0));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 0));
      // The box's own edge on the layer, and how the dashes go round it:
      // three of line, three of none, from its first corner.
      final corners = [
        onLayer(tester, c.dx, c.dy),
        onLayer(tester, c.dx + 96, c.dy),
        onLayer(tester, c.dx + 96, c.dy + 60),
        onLayer(tester, c.dx, c.dy + 60),
      ];
      final edge =
          2 * ((corners[1] - corners[0]).distance) +
          2 * ((corners[2] - corners[1]).distance);
      final dashes = <double>[];
      expect(
        chrome,
        paints
          ..path(
            includes: [
              onLayer(tester, c.dx + 48, c.dy + 30),
              onLayer(tester, c.dx + 2, c.dy + 2),
              onLayer(tester, c.dx + 94, c.dy + 58),
            ],
            excludes: [
              onLayer(tester, c.dx - 2, c.dy + 30),
              onLayer(tester, c.dx + 98, c.dy + 30),
              onLayer(tester, c.dx + 48, c.dy - 2),
              onLayer(tester, c.dx + 48, c.dy + 62),
            ],
            color: Colors.white,
            style: PaintingStyle.stroke,
            strokeWidth: 1,
          )
          ..something((method, arguments) {
            if (method != #drawPath) {
              return false;
            }
            final paint = arguments[1] as Paint;
            dashes.addAll([
              for (final dash in (arguments[0] as Path).computeMetrics())
                dash.length,
            ]);
            return paint.color.toARGB32() == 0xFF808080 &&
                paint.style == PaintingStyle.stroke &&
                paint.strokeWidth == 1;
          }),
      );
      expect(dashes.first, closeTo(3, 1e-3));
      expect(dashes, hasLength((edge / 6).ceil()));
    });

    testWidgets('🚨every text of the cel wears one, and the one in hand '
        'wears its own INSTEAD', (tester) async {
      final c = await hiInHandByItsBox(tester);
      // A second text, under the first.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      await clickAt(tester, c.dx, c.dy + 120);
      await typeText(tester, 'yo');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(celOf(tester).texts, hasLength(2), reason: '⛔fixture');
      expect(textToolOf(tester).session, isNotNull, reason: '⛔fixture');

      // 「yo」 in hand by its box: 「hi」 dashed — two paths — and the box.
      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 2 + 1));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 4 * 2));
      expect(
        chrome,
        paints..path(
          includes: [onLayer(tester, c.dx + 48, c.dy + 30)],
          excludes: [onLayer(tester, c.dx + 48, c.dy + 150)],
          color: Colors.white,
        ),
      );
      expect(chrome, crossAt(onLayer(tester, c.dx + 48, c.dy + 150)));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);

      // Both in nobody's hand: two dashed boxes, 「hi」's first — it is the
      // one underneath.
      expect(textToolOf(tester).session, isNull, reason: '⛔fixture');
      expect(chrome, paintsExactlyCountTimes(#drawPath, 2 * 2));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 0));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 0));
      expect(
        chrome,
        paints
          ..path(includes: [onLayer(tester, c.dx + 48, c.dy + 30)])
          ..path()
          ..path(includes: [onLayer(tester, c.dx + 48, c.dy + 150)]),
      );
    });

    testWidgets('a step of history that takes a text off its cel takes its '
        'box with it', (tester) async {
      await hiInHandByItsBox(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 2), reason: '⛔fixture');

      sessionOf(tester).historyManager.undo();
      await pumpFrames(tester);

      expect(celOf(tester).texts, isEmpty, reason: '⛔fixture');
      expect(
        tester.renderObject(textChrome()),
        paintsExactlyCountTimes(#drawPath, 0),
      );
    });
  });
}
