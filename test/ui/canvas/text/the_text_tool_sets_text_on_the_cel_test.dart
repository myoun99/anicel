import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton;
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
      shownPixel(canvasShows(tester), c.dx.toInt() + 10, c.dy.toInt() + 10),
      black,
      reason: '🚨the canvas draws it while it is typed',
    );
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

      // Nearer the seam between 「h」 and 「i」, which is at 48, than the
      // text's start — and below the cross in the middle of the box, which
      // a press ON takes instead (R9-rest-Q2).
      await clickAt(tester, c.dx + 30, c.dy + 55);

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
      expect(textToolOf(tester).session, isNotNull, reason: 'still in hand');
      expect(textToolOf(tester).hold, CelTextHold.box);

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
      // Taken by its box, and by its letters: two clicks, off the cross.
      await clickAt(tester, c.dx + 10, c.dy + 30);
      await clickAt(tester, c.dx + 10, c.dy + 30);
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
      // The selected letters are washed over, in place of the caret: the
      // wash, and the box.
      final chrome = tester.renderObject(textChrome());
      expect(
        chrome,
        paints..path(
          includes: [onLayer(tester, c.dx + 72, c.dy + 45)],
          excludes: [onLayer(tester, c.dx + 120, c.dy + 30)],
          style: PaintingStyle.fill,
        ),
      );
      expect(chrome, paintsExactlyCountTimes(#drawPath, 2));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 0));
    });

    testWidgets('the rail\'s ↶ says what the key says: while the letters '
        'are typed it takes a step back in THEM', (tester) async {
      final c = await textToolInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await pumpFrames(tester);

      final tool = textToolOf(tester);
      expect(tool.hold, CelTextHold.letters);
      expect(tool.letters!.text, '');
      expect(history.undoCount, steps);
      expect(
        tester.widget<EditableText>(textField()).focusNode.hasFocus,
        isTrue,
        reason: 'a press on the rail does not take the keyboard from the text',
      );
    });

    testWidgets('🚨a press on the canvas while a text is typed into leaves '
        'the keyboard with the text: the next key is still a letter\'s', (
      tester,
    ) async {
      final c = await textToolInHand(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');

      // Between the two letters: the caret goes there.
      await clickAt(tester, c.dx + 50, c.dy + 30);

      expect(
        textToolOf(tester).letters!.selection,
        const TextSelection.collapsed(offset: 1),
      );
      expect(
        tester.widget<EditableText>(textField()).focusNode.hasFocus,
        isTrue,
      );

      // 「b」 with no field holding the keyboard is the brush.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await pumpFrames(tester);

      expect(textLayer(), findsOneWidget);
      expect(textToolOf(tester).hold, CelTextHold.letters);
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

      // After 「hi」, as tall as its line — where the panel shows that, and
      // a hairline on the SCREEN however far out the view is zoomed.
      final chrome = tester.renderObject(textChrome());
      expect(
        chrome,
        paints..line(
          p1: onLayer(tester, c.dx + 96, c.dy),
          p2: onLayer(tester, c.dx + 96, c.dy + 60),
          strokeWidth: 1.5,
        ),
      );
      expect(chrome, paintsExactlyCountTimes(#drawRect, 0));
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));

      // It blinks: half a second lit, half a second not.
      await tester.pump(const Duration(milliseconds: 500));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(chrome, paintsExactlyCountTimes(#drawLine, 1));
    });

    testWidgets('a box being dragged out is drawn as it is traced, and gone '
        'when the hand comes up', (tester) async {
      final c = await textToolInHand(tester);
      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 0), reason: '⛔fixture');

      final mouse = await pressAt(tester, c.dx, c.dy);
      await mouse.moveTo(onScreen(tester, c.dx + 120, c.dy + 90));
      await tester.pump();

      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));

      await mouse.up();
      await pumpFrames(tester);

      // The box of the text that began — one box, and its caret.
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
      expect(textToolOf(tester).session!.content.wrapWidth, 120);
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
        paints..line(
          p1: onLayer(tester, c.dx + 48, c.dy + 60),
          p2: onLayer(tester, c.dx + 96, c.dy + 60),
          strokeWidth: 1.5,
        ),
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

  testWidgets('another frame taken mid-drag ends the drag where it is: the '
      'box being traced begins nothing on the cel that came', (tester) async {
    await pumpTextToolApp(tester, project: textToolProject(drawings: 2));
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    final mouse = await pressAt(tester, c.dx, c.dy);
    await mouse.moveTo(onScreen(tester, c.dx + 60, c.dy + 40));
    await tester.pump();

    sessionOf(tester).selectFrameIndex(1);
    await pumpFrames(tester);
    await mouse.moveTo(onScreen(tester, c.dx + 120, c.dy + 90));
    await mouse.up();
    await pumpFrames(tester);

    expect(textToolOf(tester).session, isNull);
    expect(
      tester.renderObject(textChrome()),
      paintsExactlyCountTimes(#drawPath, 0),
    );
  });

  testWidgets('🚨another project coming on screen lands the text in ITS OWN '
      'project first', (tester) async {
    final c = await textToolInHand(tester);
    final first = sessionOf(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');

    for (final key in ['top-strip-project-button', 'menu-file-new']) {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      // ⚠️Frames, not a settle: the caret blinks for as long as a text is
      // typed into, and a tree that keeps asking for frames never settles.
      await pumpFrames(tester, 40);
    }
    expect(
      identical(sessionOf(tester), first),
      isFalse,
      reason: '⛔fixture: another project is on screen',
    );

    expect(
      first.pixelEditing.coordinator!
          .currentSurfaceOf(textToolKey)
          .texts
          .single
          .content
          .text,
      'hi',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a button that is not the tool\'s begins nothing: the '
      'secondary one', (tester) async {
    final c = await textToolInHand(tester);

    final mouse = await tester.startGesture(
      onScreen(tester, c.dx, c.dy),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await mouse.up();
    await pumpFrames(tester);

    expect(textToolOf(tester).session, isNull);
  });

  testWidgets('🚨a save a person asked for lands the text being typed, as it '
      'is shown — and the typing goes on', (tester) async {
    final c = await textToolInHand(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    expect(celOf(tester).texts, isEmpty, reason: '⛔fixture: not landed');

    // The verb the save's door takes before it reads the project
    // (`ProjectFileDoor._settleWorkInFlight`).
    expect(sessionOf(tester).liveStrokeLanding.landNow(), isTrue);
    await pumpFrames(tester);

    expect(celOf(tester).texts.single.content.text, 'hi');
    expect(history.undoCount, steps + 1);
    expect(textToolOf(tester).hold, CelTextHold.letters);
    expect(textField(), findsOneWidget);

    await typeText(tester, 'hi!');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(celOf(tester).texts.single.content.text, 'hi!');
    expect(history.undoCount, steps + 2);
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
    // Alt held is the eyedropper under it, as under every tool that
    // does not read Alt for itself (F-299).
    expect(canvasToolReadsAlt(CanvasTool.text), isFalse);
  });
}
