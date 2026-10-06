import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

      final first = await tester.startGesture(
        onScreen(tester, c.dx + 48, c.dy + 30),
        kind: PointerDeviceKind.touch,
        pointer: 7,
      );
      await tester.pump();
      await first.moveTo(onScreen(tester, c.dx + 148, c.dy + 130));
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

  group('the box it wears', () {
    // A handle is its square, filled and then stroked: two rects.
    testWidgets('a text that grows: the box, and a handle on each corner', (
      tester,
    ) async {
      await hiInHandByItsBox(tester);

      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 4 * 2));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 0));
    });

    testWidgets('a box: one on each side edge too — what is drawn is what '
        'is grabbed', (tester) async {
      await boxInHand(tester);

      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 6 * 2));
    });

    testWidgets('with nothing in hand the tool draws nothing', (tester) async {
      await hiInHandByItsBox(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(textToolOf(tester).session, isNull, reason: '⛔fixture');

      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 0));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 0));
    });
  });
}
