import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';
import '../../../helpers/key_chords.dart';

/// 🚨★★★THE TEXT TOOL SETS TEXT ON THE CEL (R9-rest) — the real app, a real
/// mouse, the keyboard's own channel.
///
/// 🗣️유저 2026-10-02: 「클튜나 포토샵이랑 동일하게 텍스트툴로 캔버스에
/// 클릭하면 텍스트 박스가 생김. 거기서 입력 … 텍스트 레이어가 존재하지않음 …
/// 기존 그림 레이어에 텍스트툴로 텍스트 들어가고, 복수 텍스트 들어갈수있음」.
/// And the press table taken on 2026-10-06: every way out of a text
/// CONFIRMS it, one step of history for one visit.
///
/// In the test font every letter is a box one size wide — 48 at the tool's
/// own size — on a line 60 tall, so 「hi」 set at a pixel `c` fills
/// `c`–`c + (96, 60)`. `c` is the canvas pixel in the middle of the view
/// ([canvasPixelInView]).
void main() {
  const black = [0, 0, 0, 255];
  final nothing = anyOf(isNull, [0, 0, 0, 0]);

  /// The app with the text tool in hand, and the pixel the tests work at.
  Future<Offset> textToolInHand(WidgetTester tester) async {
    await pumpTextToolApp(tester);
    await takeTextTool(tester);
    expect(textLayer(), findsOneWidget, reason: 'the tool mounts its layer');
    return canvasPixelInView(tester);
  }

  /// 「hi」 set at the pixel in view and let go of — on the cel.
  Future<Offset> hiOnTheCel(WidgetTester tester) async {
    final c = await textToolInHand(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);
    expect(celOf(tester).texts, hasLength(1), reason: '⛔fixture');
    return c;
  }

  testWidgets('a click on the canvas starts a text there and the keyboard '
      'types into it; nothing is on the cel until a click away lands it — '
      'as ONE step', (tester) async {
    final c = await textToolInHand(tester);

    await clickAt(tester, c.dx, c.dy);

    final tool = textToolOf(tester);
    expect(tool.hold, CelTextHold.letters);
    expect(textField(), findsOneWidget);
    expect(
      tester.widget<EditableText>(textField()).focusNode.hasFocus,
      isTrue,
      reason: 'the keyboard is the text\'s',
    );

    await typeText(tester, 'hi');

    expect(tool.session!.shown.content.text, 'hi', reason: 'it is shown');
    expect(
      celOf(tester).texts,
      isEmpty,
      reason: 'a text being typed is not on its cel yet',
    );

    await clickAt(tester, c.dx + 300, c.dy + 200);

    final texts = celOf(tester).texts;
    expect(texts, hasLength(1));
    expect(texts.single.content.text, 'hi');
    expect(texts.single.content.anchor, CanvasPoint(x: c.dx, y: c.dy));
    expect(texts.single.content.wrapWidth, isNull, reason: 'a click: it grows');
    final x = c.dx.toInt();
    final y = c.dy.toInt();
    expect(shownPixel(celOf(tester), x + 10, y + 10), black);
    expect(shownPixel(celOf(tester), x + 100, y + 10), nothing);
    expect(tool.session, isNull, reason: 'the click away let go of it');
    expect(textField(), findsNothing);

    final history = sessionOf(tester).historyManager;
    history.undo();
    await pumpFrames(tester);
    expect(celOf(tester).texts, isEmpty, reason: 'one step back: no text');
    history.redo();
    await pumpFrames(tester);
    expect(celOf(tester).texts.single.content.text, 'hi');
  });

  testWidgets('a text with no letters typed leaves nothing — no text, and '
      'no step of history', (tester) async {
    final c = await textToolInHand(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await clickAt(tester, c.dx, c.dy);
    expect(textToolOf(tester).session, isNotNull, reason: '⛔fixture: begun');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(textToolOf(tester).session, isNull);
    expect(celOf(tester).texts, isEmpty);
    expect(history.undoCount, steps);
  });

  testWidgets('Esc lets go of the LETTERS and the text stays in hand by its '
      'box, landed; Esc again lets go of it', (tester) async {
    final c = await textToolInHand(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    final tool = textToolOf(tester);
    expect(tool.hold, CelTextHold.box);
    expect(tool.session, isNotNull);
    expect(textField(), findsNothing);
    expect(celOf(tester).texts.single.content.text, 'hi');
    expect(tool.session!.textId, celOf(tester).texts.single.id);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    expect(tool.session, isNull);
    expect(celOf(tester).texts, hasLength(1), reason: 'the text stays');
  });

  group('a text the cel already carries', () {
    testWidgets('a click on it takes it by its box; a second click opens its '
        'letters, the caret where the click was', (tester) async {
      final c = await hiOnTheCel(tester);
      final tool = textToolOf(tester);

      await clickAt(tester, c.dx + 10, c.dy + 30);

      expect(tool.session!.textId, celOf(tester).texts.single.id);
      expect(tool.hold, CelTextHold.box);
      expect(textField(), findsNothing);

      // Just past the seam between 「h」 and 「i」, which is at 48.
      await clickAt(tester, c.dx + 50, c.dy + 30);

      expect(tool.hold, CelTextHold.letters);
      expect(tool.letters!.selection, const TextSelection.collapsed(offset: 1));
    });

    testWidgets('a drag inside it moves it by whole pixels — one step, and '
        'the letters are where the text is', (tester) async {
      final c = await hiOnTheCel(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;

      await dragFrom(
        tester,
        Offset(c.dx + 10, c.dy + 30),
        Offset(c.dx + 110.4, c.dy + 110.6),
      );

      final moved = celOf(tester).texts.single;
      expect(moved.content.anchor, CanvasPoint(x: c.dx + 100, y: c.dy + 81));
      expect(history.undoCount, steps + 1);
      final x = c.dx.toInt();
      final y = c.dy.toInt();
      expect(shownPixel(celOf(tester), x + 110, y + 91), black);
      expect(shownPixel(celOf(tester), x + 10, y + 10), nothing);
      expect(textToolOf(tester).hold, CelTextHold.box, reason: 'still in hand');

      history.undo();
      await pumpFrames(tester);
      expect(
        celOf(tester).texts.single.content.anchor,
        CanvasPoint(x: c.dx, y: c.dy),
      );
    });

    testWidgets('Delete takes the text in hand off its cel — one step', (
      tester,
    ) async {
      final c = await hiOnTheCel(tester);
      await clickAt(tester, c.dx + 10, c.dy + 30);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await pumpFrames(tester);

      expect(celOf(tester).texts, isEmpty);
      expect(textToolOf(tester).session, isNull);
      expect(history.undoCount, steps + 1);
      history.undo();
      await pumpFrames(tester);
      expect(celOf(tester).texts.single.content.text, 'hi');
    });

    testWidgets('a click outside it lets go of it and changes nothing', (
      tester,
    ) async {
      final c = await hiOnTheCel(tester);
      await clickAt(tester, c.dx + 10, c.dy + 30);
      expect(textToolOf(tester).session, isNotNull, reason: '⛔fixture');
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final before = celOf(tester);

      await clickAt(tester, c.dx + 300, c.dy + 200);

      expect(textToolOf(tester).session, isNull);
      expect(celOf(tester), same(before));
      expect(history.undoCount, steps);
    });

    testWidgets('a second text goes ON TOP of the first', (tester) async {
      final c = await hiOnTheCel(tester);

      await clickAt(tester, c.dx, c.dy + 120);
      await typeText(tester, 'yo');
      await clickAt(tester, c.dx + 300, c.dy + 200);

      expect(
        [for (final text in celOf(tester).texts) text.content.text],
        ['hi', 'yo'],
      );
    });
  });

  group('the letters', () {
    testWidgets('a drag across them selects them, from where the press '
        'went down', (tester) async {
      final c = await hiOnTheCel(tester);
      await clickAt(tester, c.dx + 10, c.dy + 30);
      await clickAt(tester, c.dx + 50, c.dy + 30);
      final tool = textToolOf(tester);
      expect(tool.hold, CelTextHold.letters, reason: '⛔fixture');

      await dragFrom(
        tester,
        Offset(c.dx + 5, c.dy + 30),
        Offset(c.dx + 90, c.dy + 30),
      );

      expect(tool.hold, CelTextHold.letters);
      expect(
        tool.letters!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
    });

    testWidgets('🚨Ctrl+Z while they are typed takes a step back in the '
        'LETTERS — history is not touched, and the text stays in hand', (
      tester,
    ) async {
      final c = await textToolInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');

      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      await pumpFrames(tester);

      final tool = textToolOf(tester);
      expect(tool.hold, CelTextHold.letters);
      expect(tool.letters!.text, '');
      expect(tool.session!.shown.content.isEmpty, isTrue);
      expect(history.undoCount, steps);
      expect(celOf(tester).texts, isEmpty);
    });

    testWidgets('Ctrl+Z with the text held by its BOX is the document\'s: '
        'the text is let go of, and the step that set it is taken back', (
      tester,
    ) async {
      final c = await textToolInHand(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(celOf(tester).texts, hasLength(1), reason: '⛔fixture');
      expect(textToolOf(tester).hold, CelTextHold.box, reason: '⛔fixture');

      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      await pumpFrames(tester);

      expect(celOf(tester).texts, isEmpty);
      expect(textToolOf(tester).session, isNull);
    });

    testWidgets('the caret is drawn where the text ON SCREEN puts it, and a '
        'text being typed wears no handles', (tester) async {
      final c = await textToolInHand(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');

      final caret = textToolOf(tester).session!.shown.layout.caretRect(
        const TextPosition(offset: 2),
      );
      expect(caret.topLeft, const Offset(96, 0), reason: '⛔fixture');
      expect(caret.bottomLeft, const Offset(96, 60), reason: '⛔fixture');
      final chrome = tester.renderObject(textChrome());
      expect(
        chrome,
        paints..line(p1: const Offset(96, 0), p2: const Offset(96, 60)),
      );
      expect(chrome, paintsExactlyCountTimes(#drawRect, 0));
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
    });

    testWidgets('the letters an IME is still composing wear a line under '
        'them', (tester) async {
      final c = await textToolInHand(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawLine, 1), reason: '⛔caret');

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      await pumpFrames(tester);

      // Under 「i」: from its left edge to its right, at the foot of its line.
      expect(
        chrome,
        paints..line(p1: const Offset(48, 60), p2: const Offset(96, 60)),
      );
      expect(chrome, paintsExactlyCountTimes(#drawLine, 2));
    });
  });

  testWidgets('🚨another frame taken lands the text on ITS cel — the one it '
      'was typed on (유저 2026-10-06: 「주인은 셀임」)', (tester) async {
    await pumpTextToolApp(tester, project: textToolProject(drawings: 2));
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');

    sessionOf(tester).selectFrameIndex(1);
    await pumpFrames(tester);

    expect(celOf(tester).texts.single.content.text, 'hi');
    expect(celOf(tester, textToolSecondKey).texts, isEmpty);
    expect(textToolOf(tester).session, isNull);
    expect(history.undoCount, steps + 1);
  });

  testWidgets('🚨with the ENGINE itself setting the text: what is typed is '
      'on the canvas as the engine draws it, and lands as that', (
    tester,
  ) async {
    await pumpTextToolApp(tester, engine: true);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await settleWithTheEngine(tester);
    expect(textToolOf(tester).session!.shown.content.text, 'hi');

    await clickAt(tester, c.dx + 300, c.dy + 200);

    final landed = celOf(tester);
    final x = c.dx.toInt();
    final y = c.dy.toInt();
    expect(landed.texts.single.content.text, 'hi');
    // The test font's letters are boxes one size square, standing 6 down a
    // line 60 tall.
    expect(shownPixel(landed, x + 10, y + 30), black);
    expect(
      shownPixel(landed, x + 10, y + 2),
      nothing,
      reason: 'above the letters, inside their line: the engine drew this',
    );
    expect(shownPixel(landed, x + 100, y + 30), nothing);
  });

  testWidgets('a DRAG on the empty canvas starts a box as wide as the drag, '
      'hung from its top left corner', (tester) async {
    final c = await textToolInHand(tester);

    await dragFrom(tester, Offset(c.dx + 220, c.dy + 190), c);

    final tool = textToolOf(tester);
    expect(tool.hold, CelTextHold.letters);
    expect(tool.session!.content.anchor, CanvasPoint(x: c.dx, y: c.dy));
    expect(tool.session!.content.wrapWidth, 220);
  });

  testWidgets('🚨the brush does not draw with the text tool in hand', (
    tester,
  ) async {
    final c = await textToolInHand(tester);

    await dragFrom(tester, c, Offset(c.dx + 200, c.dy + 120));
    expect(textToolOf(tester).session, isNotNull, reason: '⛔fixture: a box');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    expect(celOf(tester).tiles, isEmpty, reason: 'no stroke was drawn');
    expect(celOf(tester).texts, isEmpty);
  });

  testWidgets('another tool taken in hand lands the text being typed', (
    tester,
  ) async {
    final c = await textToolInHand(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');

    await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));
    await pumpFrames(tester);

    expect(textLayer(), findsNothing);
    expect(celOf(tester).texts.single.content.text, 'hi');
  });

  testWidgets('🚨a key pressed while a text is typed into is the text\'s, '
      'not the app\'s shortcut for it', (tester) async {
    await textToolInHand(tester);

    // ⛔Fixture: with no text in hand, B is the brush — the layer goes.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await pumpFrames(tester);
    expect(textLayer(), findsNothing, reason: '⛔fixture: B takes the brush');

    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await pumpFrames(tester);

    expect(textLayer(), findsOneWidget, reason: 'the text tool is in hand');
    expect(textToolOf(tester).hold, CelTextHold.letters);
  });

  test('the text tool is a tool that puts something on a cel', () {
    expect(canvasToolMarksCel(CanvasTool.text), isTrue);
    expect(canvasToolPaints(CanvasTool.text), isFalse);
    expect(canvasToolSelects(CanvasTool.text), isFalse);
    expect(canvasToolTakesDrawingPress(CanvasTool.text), isFalse);
  });
}
