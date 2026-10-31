import 'package:anicel/src/native/windows_key_state.dart';
import 'package:anicel/src/services/input/modifier_keys.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerDownEvent, PointerUpEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';

/// 🗣️F-523 (유저 2026-11-01): 「분명 텍스트 편집중에 컨트롤누를때 이동가능한거,
/// 그게아니라 애초에 변형 가능한 상태로 진입하게하라고 하지않았나. 누른동안
/// 꼭짓점에 사각형생기고 그런거」 — the real app, a real keyboard and mouse.
///
/// In the test font 「hi」 at the tool's own size is 96 wide on a line 60 tall:
/// its box stands from `c - (12, 12)` to `c + (108, 72)`, its centre at
/// `c + (48, 30)`.
void main() {
  const ctrl = LogicalKeyboardKey.controlLeft;

  /// 「hi」 on the cel at the pixel in view, its letters held.
  Future<Offset> hiBeingTyped(WidgetTester tester) async {
    await pumpTextToolApp(tester);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    expect(textToolOf(tester).hold, CelTextHold.letters, reason: '⛔fixture');
    return c;
  }

  /// A handle is its square, filled and then stroked: two rects.
  Matcher handles(int count) => paintsExactlyCountTimes(#drawRect, count * 2);

  void expectStillTyped(WidgetTester tester) {
    expect(textToolOf(tester).hold, CelTextHold.letters);
    expect(
      textToolOf(tester).letters!.selection,
      const TextSelection.collapsed(offset: 2),
      reason: 'the caret stays where it was',
    );
  }

  testWidgets('🚨while Ctrl is held the text wears its handles, and let go '
      'it does not', (tester) async {
    await hiBeingTyped(tester);
    expect(tester.renderObject(textChrome()), handles(0));

    await tester.sendKeyDownEvent(ctrl);
    await tester.pump();
    expect(tester.renderObject(textChrome()), handles(4));

    await tester.sendKeyUpEvent(ctrl);
    await tester.pump();
    expect(tester.renderObject(textChrome()), handles(0));
    expectStillTyped(tester);
  });

  testWidgets('⌘ is Ctrl on a Mac or an iPad', (tester) async {
    await hiBeingTyped(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(tester.renderObject(textChrome()), handles(4));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  testWidgets('a finger resting on the glass is a tablet\'s Ctrl, and one '
      'lifting lets go', (tester) async {
    await hiBeingTyped(tester);
    addTearDown(CanvasTouchContacts.reset);

    CanvasTouchContacts.noteAppWide(
      const PointerDownEvent(pointer: 40, kind: PointerDeviceKind.touch),
    );
    await tester.pump();
    expect(tester.renderObject(textChrome()), handles(4));

    CanvasTouchContacts.noteAppWide(
      const PointerUpEvent(pointer: 40, kind: PointerDeviceKind.touch),
    );
    await tester.pump();
    expect(tester.renderObject(textChrome()), handles(0));
  });

  testWidgets('⚠️a Ctrl whose release the engine never hands over is let go '
      'at the next hover (I-61)', (tester) async {
    final c = await hiBeingTyped(tester);
    addTearDown(() => ModifierKeys.debugWindowsKeyDown = null);
    var down = true;
    ModifierKeys.debugWindowsKeyDown = (key) => down && key == vkControl;

    await tester.sendKeyDownEvent(ctrl);
    await tester.pump();
    expect(tester.renderObject(textChrome()), handles(4));

    // A pen's hover lets the key go in the engine's record, and Windows
    // still has it down.
    await tester.sendKeyUpEvent(ctrl);
    await tester.pump();
    expect(tester.renderObject(textChrome()), handles(4));

    // The real release is heard by nobody.
    down = false;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(onScreen(tester, c.dx + 200, c.dy));
    await tester.pump();

    expect(tester.renderObject(textChrome()), handles(0));
  });

  group('with Ctrl held', () {
    testWidgets('🚨a corner sizes it, its letters still held, and what is '
        'typed next goes into it as sized', (tester) async {
      final c = await hiBeingTyped(tester);
      final size = () => textToolOf(
        tester,
      ).contentInHand!.spans.first.style.fontSize;
      final before = size();

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      await dragFrom(
        tester,
        Offset(c.dx + 108, c.dy + 72),
        Offset(c.dx + 168, c.dy + 114),
      );
      await tester.sendKeyUpEvent(ctrl);
      await pumpFrames(tester);

      expect(size(), closeTo(before * 2, before * 0.02));
      expectStillTyped(tester);

      await typeText(tester, 'hi!');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(celOf(tester).texts.single.content.text, 'hi!');
      expect(
        celOf(tester).texts.single.content.spans.first.style.fontSize,
        closeTo(before * 2, before * 0.02),
      );
    });

    testWidgets('🚨the side edge of a box sets its width', (tester) async {
      await pumpTextToolApp(tester);
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await dragFrom(tester, c, Offset(c.dx + 220, c.dy + 190));
      await typeText(tester, 'hi');
      final width = textToolOf(tester).contentInHand!.wrapWidth!;

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      expect(tester.renderObject(textChrome()), handles(8));
      await dragFrom(
        tester,
        Offset(c.dx + 220, c.dy + 95),
        Offset(c.dx + 260, c.dy + 95),
      );
      await tester.sendKeyUpEvent(ctrl);
      await pumpFrames(tester);

      expect(textToolOf(tester).contentInHand!.wrapWidth, width + 40);
      expect(textToolOf(tester).hold, CelTextHold.letters);
    });

    testWidgets('🚨its cross is carried', (tester) async {
      final c = await hiBeingTyped(tester);

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      await dragFrom(
        tester,
        Offset(c.dx + 48, c.dy + 30),
        Offset(c.dx + 78, c.dy + 50),
      );
      await tester.sendKeyUpEvent(ctrl);
      await pumpFrames(tester);

      final cross = textToolOf(tester).crossOffCentre;
      expect(cross.dx, closeTo(30, 1e-6));
      expect(cross.dy, closeTo(20, 1e-6));
      expectStillTyped(tester);
    });

    testWidgets('🚨dragged outside the box it turns, and let go where it went '
        'down outside, the tool lets go of it — the box\'s own table', (
      tester,
    ) async {
      final c = await hiBeingTyped(tester);

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      await dragFrom(
        tester,
        Offset(c.dx + 200, c.dy + 30),
        Offset(c.dx + 48, c.dy + 180),
      );
      await tester.pump();
      expect(textToolOf(tester).contentInHand!.rotationDegrees, isNot(0));
      expect(textToolOf(tester).hold, CelTextHold.letters);

      await clickAt(tester, c.dx + 300, c.dy + 30);
      await tester.sendKeyUpEvent(ctrl);
      await pumpFrames(tester);
      expect(textToolOf(tester).session, isNull);
    });

    testWidgets('inside the box it carries the text, as it did (I-96)', (
      tester,
    ) async {
      final c = await hiBeingTyped(tester);

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      await dragFrom(
        tester,
        Offset(c.dx + 10, c.dy + 30),
        Offset(c.dx + 30, c.dy + 45),
      );
      await tester.sendKeyUpEvent(ctrl);
      await pumpFrames(tester);

      final anchor = textToolOf(tester).contentInHand!.anchor;
      expect(anchor.x, c.dx + 20);
      expect(anchor.y, c.dy + 15);
      expectStillTyped(tester);
    });

    testWidgets('🚨the keyboard stays the field\'s: Ctrl+A selects its '
        'letters, not the text', (tester) async {
      await hiBeingTyped(tester);

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(ctrl);
      await tester.pump();

      expect(
        textToolOf(tester).letters?.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
    });

    testWidgets('the mouse wears the box\'s cursor, not the caret\'s', (
      tester,
    ) async {
      await hiBeingTyped(tester);
      MouseCursor cursor() => tester
          .widget<MouseRegion>(
            find.ancestor(of: textLayer(), matching: find.byType(MouseRegion)).first,
          )
          .cursor;
      expect(cursor(), SystemMouseCursors.text);

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      expect(cursor(), MouseCursor.defer);

      await tester.sendKeyUpEvent(ctrl);
      await tester.pump();
      expect(cursor(), SystemMouseCursors.text);
    });

    testWidgets('let go in the middle of a drag, the box stays on until the '
        'hand comes up', (tester) async {
      final c = await hiBeingTyped(tester);

      await tester.sendKeyDownEvent(ctrl);
      await tester.pump();
      final hand = await pressAt(tester, c.dx + 108, c.dy + 72);
      await hand.moveBy(const Offset(20, 15));
      await tester.pump();
      await tester.sendKeyUpEvent(ctrl);
      await tester.pump();
      expect(tester.renderObject(textChrome()), handles(4));

      await hand.up();
      await pumpFrames(tester);
      expect(tester.renderObject(textChrome()), handles(0));
    });
  });
}
