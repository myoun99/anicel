import 'dart:async';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/app_shortcuts.dart';
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
      await canvasPixel(tester, c.dx.toInt() + 10, c.dy.toInt() + 10),
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
      // Delete is 삭제 on the registry's keys — Clip Studio's is its Erase.
      await useAnicelKeys(tester);
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

    // 🗣️I-96 (유저 2026-10-12): 「편집중이던 뭐던 컨트롤 누르고 상자 이동
    // 가능하도록. ae에도 있던 기능인거같은데」.
    testWidgets('🚨with Ctrl held a drag inside the text being typed into '
        'carries it — still typed into, and a click away lands it where it '
        'was carried, as ONE step', (tester) async {
      final c = await textToolInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await dragFrom(
        tester,
        Offset(c.dx + 10, c.dy + 30),
        Offset(c.dx + 110.4, c.dy + 110.6),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      final tool = textToolOf(tester);
      final carried = CanvasPoint(x: c.dx + 100, y: c.dy + 81);
      expect(tool.hold, CelTextHold.letters);
      expect(tool.letters!.content.anchor, carried);
      expect(
        tool.letters!.selection,
        const TextSelection.collapsed(offset: 2),
        reason: 'no caret was set',
      );
      expect(
        tester.widget<EditableText>(textField()).focusNode.hasFocus,
        isTrue,
      );

      await typeText(tester, 'hiya');
      await clickAt(tester, c.dx + 300, c.dy + 200);

      final landed = celOf(tester).texts.single;
      expect(landed.content.text, 'hiya');
      expect(landed.content.anchor, carried);
      expect(history.undoCount, steps + 1);
      final x = c.dx.toInt();
      final y = c.dy.toInt();
      expect(shownPixel(celOf(tester), x + 110, y + 91), black);
      expect(shownPixel(celOf(tester), x + 10, y + 10), nothing);
    });

    // 🗣️I-96-Q3 (유저 2026-10-16, a): 「손가락도 — 늘 켜짐(변형 · 도형처럼)」
    // — a finger resting on the glass is a tablet's Ctrl.
    testWidgets('🚨with a FINGER resting on the glass, a pen dragged inside '
        'the text being typed into carries it as Ctrl does — and the finger '
        'lifted, it is still typed into', (tester) async {
      addTearDown(() => AppInput.settings.value = const AppInputSettings());
      final c = await textToolInHand(tester);
      // One finger moves the view: resting, it does nothing of its own.
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.navigate,
      );
      await pumpFrames(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');

      final finger = await pressAt(
        tester,
        c.dx + 300,
        c.dy + 200,
        kind: PointerDeviceKind.touch,
      );
      await dragFrom(
        tester,
        Offset(c.dx + 10, c.dy + 30),
        Offset(c.dx + 110.4, c.dy + 110.6),
        kind: PointerDeviceKind.stylus,
      );
      await finger.up();
      await pumpFrames(tester);

      final tool = textToolOf(tester);
      final carried = CanvasPoint(x: c.dx + 100, y: c.dy + 81);
      expect(tool.hold, CelTextHold.letters);
      expect(tool.letters!.content.anchor, carried);
      expect(
        tool.letters!.selection,
        const TextSelection.collapsed(offset: 2),
        reason: 'no caret was set',
      );

      await typeText(tester, 'hiya');
      await clickAt(tester, c.dx + 300, c.dy + 200);

      final landed = celOf(tester).texts.single;
      expect(landed.content.text, 'hiya');
      expect(landed.content.anchor, carried);
      expect(history.undoCount, steps + 1);
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

      // The box of the text that began — one box, and its caret: its
      // letters 12 in from either side of it.
      expect(chrome, paintsExactlyCountTimes(#drawPath, 1));
      expect(textToolOf(tester).session!.content.wrapWidth, 96);
      expect(textToolOf(tester).session!.content.minHeight, 66);
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

  // 🗣️TS9, 유저: 「1핑거가 플립모드인데도 선택툴고르고 터치하면 선택이
  // 작동함. 드로잉모드가 아닌이상은 툴이 작동하면 안되지」 — said of the
  // selection tool, and the law of every tool's layer
  // (`AppInput.toolAcceptsPointer`).
  testWidgets('🚨a FINGER begins a text only while one finger draws: in any '
      'other mode the finger is the view\'s', (tester) async {
    addTearDown(() => AppInput.settings.value = const AppInputSettings());
    final c = await textToolInHand(tester);
    // One finger moves the view (it draws, as the app starts).
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.navigate,
    );
    await pumpFrames(tester);
    expect(AppInput.touchDraws, isFalse, reason: '⛔fixture');

    Future<void> tapWithAFinger() async {
      final finger = await tester.startGesture(
        onScreen(tester, c.dx, c.dy),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.up();
      await pumpFrames(tester);
    }

    await tapWithAFinger();

    expect(textToolOf(tester).session, isNull);
    expect(textField(), findsNothing);

    // ⛔CONTROL: the very tap, once one finger draws, begins one.
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await pumpFrames(tester);
    await tapWithAFinger();

    expect(textToolOf(tester).session, isNotNull);
    expect(textField(), findsOneWidget);
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

  group('🚨the step a walk landed was made where the text was held — I-41 '
      '(board undo-walks-to-the-frame-a-text-landed-from)', () {
    /// A text typed on frame 0's cel, landed by [walkOff] — standing back
    /// on frame 0's cel after it when [back].
    Future<EditorSessionManager> typedThenWalkedOff(
      WidgetTester tester, {
      required void Function(EditorSessionManager session) walkOff,
      required bool back,
    }) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(
          drawings: 2,
          emptyLayer: true,
          secondCut: true,
        ),
      );
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      final session = sessionOf(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      walkOff(session);
      await pumpFrames(tester);
      // The store's: the canvas the walk took them to may be another size
      // than the cel's, and its session would read the cel blank.
      final carried = coordinatorOf(
        tester,
      ).frameStore.bakedSurfaceOrNull(textToolKey);
      expect(carried?.texts.single.content.text, 'hi', reason: '⛔');
      if (back) {
        if (session.activeCutId != textToolCutId) {
          session.selectCut(textToolCutId);
        }
        session.selectLayer(textToolLayerId);
        session.selectFrameIndex(0);
        await pumpFrames(tester);
      }
      return session;
    }

    // Every door that moves where the user stands (`EditorSessionManager`'s
    // I-41 doors): each walks off, and the hand it lets go of lands there.
    final walks = <String, void Function(EditorSessionManager)>{
      'another frame': (session) => session.selectFrameIndex(1),
      'another layer': (session) => session.selectLayer(textToolEmptyLayerId),
      'another row': (session) =>
          session.standOnRow(const LayerRowAddress(textToolEmptyLayerId)),
      'another cut': (session) => session.selectCut(textToolSecondCutId),
      // A gap's canvas is not the cut's (board
      // `a-text-walked-into-a-gap-lands-at-its-size`).
      'a gap': (session) => session.parkGlobalFrame(60),
    };
    for (final MapEntry(key: walk, value: walkOff) in walks.entries) {
      testWidgets('$walk: back where it was typed, ONE undo takes it back', (
        tester,
      ) async {
        final session = await typedThenWalkedOff(
          tester,
          walkOff: walkOff,
          back: true,
        );

        session.undo();
        await pumpFrames(tester);

        expect(celOf(tester).texts, isEmpty, reason: 'no walk first');
        expect(session.activeCutId, textToolCutId);
        expect(session.standingPlace?.frame, 0);
        expect(session.activeLayerId, textToolLayerId);
      });

      testWidgets('$walk: from where the walk took them, the first undo '
          'walks back to it and the next takes it back', (tester) async {
        final session = await typedThenWalkedOff(
          tester,
          walkOff: walkOff,
          back: false,
        );

        session.undo();
        await pumpFrames(tester);

        expect(session.activeCutId, textToolCutId, reason: 'walked back');
        expect(session.standingPlace?.frame, 0);
        expect(session.activeLayerId, textToolLayerId);
        expect(celOf(tester).texts.single.content.text, 'hi');

        session.undo();
        await pumpFrames(tester);

        expect(celOf(tester).texts, isEmpty);
      });
    }

    testWidgets('🚨walked into a gap, it lands on its cel at the cut\'s own '
        'size, and the cel keeps all it carried (board '
        'a-text-walked-into-a-gap-lands-at-its-size)', (tester) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(drawings: 2, secondCut: true),
      );
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      final session = sessionOf(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await clickAt(tester, c.dx + 300, c.dy + 200);
      final size = celOf(tester).canvasSize;
      await clickAt(tester, c.dx, c.dy + 120);
      await typeText(tester, 'yo');

      session.parkGlobalFrame(60);
      await pumpFrames(tester);
      expect(session.activeCutId, isNull, reason: '⛔premise: a gap');
      session.selectCut(textToolCutId);
      session.selectFrameIndex(0);
      await pumpFrames(tester);

      expect([for (final text in celOf(tester).texts) text.content.text], [
        'hi',
        'yo',
      ]);
      expect(celOf(tester).canvasSize, size);
    });

    // ↩️It landed once set, after the walk (2026-10-29 morning), and by then
    // the canvas could be the walk's: a gap's, or another cut's size, and
    // the cel lost all it carried (board
    // `a-text-walked-into-a-gap-lands-at-its-size`). Now the door lands it
    // as it is SHOWN, as an undo or another project coming on screen does —
    // what was never on screen is given up (유저 2026-09-17: 「보이는
    // 중이랑 결과랑 절대로 다르면 안 되」).
    testWidgets('walked off while the engine was still setting it: what is '
        'shown lands at the door, made where it was held', (tester) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(drawings: 2),
      );
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      final session = sessionOf(tester);
      final steps = session.historyManager.undoCount;
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'h');
      final set = Completer<void>();
      debugCelTextBaker = (
        layout, {
        required pasteboard,
        required tileSize,
        previous = const {},
      }) async {
        await set.future;
        return boxFillingBake(
          layout,
          pasteboard: pasteboard,
          tileSize: tileSize,
          previous: previous,
        );
      };
      await typeText(tester, 'hi');
      expect(textToolOf(tester).session?.settled, isFalse, reason: 'premise');
      session.selectFrameIndex(1);

      expect(celOf(tester).texts.single.content.text, 'h', reason: 'at once');
      await pumpFrames(tester);
      set.complete();
      await pumpFrames(tester);
      expect(celOf(tester).texts.single.content.text, 'h');
      expect(session.historyManager.undoCount, steps + 1);

      session.undo();
      await pumpFrames(tester);

      expect(session.standingPlace?.frame, 0, reason: 'walked back');
      expect(celOf(tester).texts.single.content.text, 'h');

      session.undo();
      await pumpFrames(tester);

      expect(celOf(tester).texts, isEmpty);
    });
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
    // 🎯The drag IS the box: its letters go in from its edges as far as
    // every text's box reaches past its letters — a quarter of their 48
    // (R9-rest, 유저 2026-10-08) — so its top edge stays where it was traced.
    final [topLeft, topRight, _, _] = tool.session!.shown.layout.boxCorners;
    expect(topLeft, c);
    expect(topRight, Offset(c.dx + 220, c.dy));
    expect(
      tool.session!.content.anchor,
      CanvasPoint(x: c.dx + 12, y: c.dy + 12),
    );
    expect(tool.session!.content.wrapWidth, 196);
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
