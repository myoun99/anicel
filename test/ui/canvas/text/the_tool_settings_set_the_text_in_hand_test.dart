import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';

/// 🚨★★★THE TOOL SETTINGS AND THE TEXT ON THE CANVAS (R9-rest) — the real
/// app, the real panel, a real mouse.
///
/// 🗣️유저 2026-10-02: 「선택해서 그 상태에서 도구설정에서 폰트바꾸면 해당
/// 텍스트박스 설정 자동으로 바꿈. 포토샵처럼 텍스트 선택하고 폰트바꿔야
/// 바뀌는게아님. 그냥 설정바꾸면 해당 텍스트박스 내 텍스트 전체에 적용되서
/// 바뀌고, 텍스트를 선택하고 조절하면 일부만 텍스트 조절」.
///
/// What a row reads and writes is measured on its own
/// (`text_tool_settings_values_test`), and the rows on theirs
/// (`text_tool_settings_test`). Here: the panel the app mounts is wired to
/// the hand the canvas holds — and using it does not take the keyboard from
/// a text being typed.
void main() {
  Finder row(String name) => find.byKey(ValueKey<String>('text-tool-$name'));

  /// The real app with the text tool in hand and its settings on screen.
  ///
  /// ⚠️In a TALL window. At the harness's own 900 the rail's open groups
  /// run past its end and the settings group — the last of them — is half
  /// out of the rail's view: its rows are laid out and cannot be pressed
  /// (measured 2026-10-06: every row under the first hit the canvas).
  Future<void> pumpWithSettings(WidgetTester tester, {Project? project}) async {
    await pumpTextToolApp(
      tester,
      size: const Size(1600, 1500),
      project: project,
    );
    await takeTextTool(tester);
    final settingsGroup = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$settingsGroup')));
    await pumpFrames(tester);
    expect(find.byType(ToolSettingsPanel), findsOneWidget, reason: '⛔fixture');
    expect(row('bold'), findsOneWidget, reason: '⛔fixture');
  }

  /// 「hi」 on the cel at the pixel in view, in hand by its box.
  Future<Offset> hiInHand(WidgetTester tester, {Project? project}) async {
    await pumpWithSettings(tester, project: project);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(textToolOf(tester).hold, CelTextHold.box, reason: '⛔fixture');
    expect(textToolOf(tester).session, isNotNull, reason: '⛔fixture');
    return c;
  }

  /// Brings the row [name] of the settings on screen: the panel is shorter
  /// than its rows, and a row far enough down is not even built until the
  /// list reaches it.
  ///
  /// ⚠️The list is MOVED, not dragged: a drag that starts on a bar is the
  /// bar's (the press law), and the middle of this list is bars.
  Future<void> reach(WidgetTester tester, String name) async {
    if (row(name).evaluate().isEmpty) {
      final list = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey<String>('tool-settings-text')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      list.jumpTo(list.maxScrollExtent);
      await pumpFrames(tester);
    }
    await tester.ensureVisible(row(name));
    await pumpFrames(tester);
  }

  /// Presses the row [name] of the settings, brought on screen first.
  Future<void> press(WidgetTester tester, String name) async {
    await reach(tester, name);
    await tester.tap(row(name));
    await pumpFrames(tester);
  }

  List<TextLetterStyle> stylesOnCel(WidgetTester tester) => [
    for (final span in celOf(tester).texts.single.content.spans) span.style,
  ];

  testWidgets('🚨a setting pressed reaches the WHOLE text in hand — one '
      'step, the text still in hand — and one undo takes it back', (
    tester,
  ) async {
    await hiInHand(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await press(tester, 'bold');

    expect(stylesOnCel(tester).single.bold, isTrue);
    expect(history.undoCount, steps + 1);
    expect(textToolOf(tester).session, isNotNull, reason: 'in hand');

    history.undo();
    await pumpFrames(tester);

    expect(stylesOnCel(tester).single.bold, isFalse);
  });

  testWidgets('🚨with letters SELECTED it reaches those alone', (tester) async {
    final c = await hiInHand(tester);
    // Into the letters — a click inside the box, beside the cross in its
    // middle — and across the second one: 「i」 stands from 48 to 96 along
    // the line.
    await clickAt(tester, c.dx + 20, c.dy + 12);
    await dragFrom(
      tester,
      Offset(c.dx + 50, c.dy + 30),
      Offset(c.dx + 95, c.dy + 30),
    );
    expect(
      textToolOf(tester).letters!.selection,
      const TextSelection(baseOffset: 1, extentOffset: 2),
      reason: '⛔fixture',
    );

    await press(tester, 'bold');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    final spans = celOf(tester).texts.single.content.spans;
    expect([for (final span in spans) span.text], ['h', 'i']);
    expect([for (final span in spans) span.style.bold], [false, true]);
  });

  testWidgets('🚨a setting pressed while a text is TYPED INTO leaves the '
      'keyboard with the text: the next key is a letter', (tester) async {
    await pumpWithSettings(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    final field = tester.widget<EditableText>(textField());
    expect(field.focusNode.hasFocus, isTrue, reason: '⛔fixture');

    await press(tester, 'bold');
    await press(tester, 'align-center');

    expect(
      tester.widget<EditableText>(textField()).focusNode.hasFocus,
      isTrue,
    );
    expect(textToolOf(tester).letters, isNotNull, reason: 'still typing');

    await typeText(tester, 'his');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    final landed = celOf(tester).texts.single.content;
    expect(landed.text, 'his');
    expect(landed.spans.single.style.bold, isTrue);
    expect(landed.align, TextCelAlign.center);
  });

  testWidgets('with NOTHING in hand a setting is the next text\'s: the '
      'letters typed after it wear it', (tester) async {
    await pumpWithSettings(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await press(tester, 'bold');
    expect(history.undoCount, steps, reason: 'nothing to land on');

    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    expect(stylesOnCel(tester).single.bold, isTrue);
  });

  testWidgets('the delete beside the text\'s name takes it off its cel — '
      'one step', (tester) async {
    await hiInHand(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await press(tester, 'delete-text');

    expect(celOf(tester).texts, isEmpty);
    expect(textToolOf(tester).session, isNull);
    expect(history.undoCount, steps + 1);

    history.undo();
    await pumpFrames(tester);

    expect(celOf(tester).texts.single.content.text, 'hi');
  });

  // 🗣️유저 2026-10-06: 「텍스트 그림으로 굳히기 아이디어 좋네 … 나중에
  // 도구설정에 등장시키기로. 동작은 텍스트 선택하면 해당 버튼 활성화색」.
  group('「그림으로 굳히기」', () {
    FilledButton button(WidgetTester tester) =>
        tester.widget<FilledButton>(row('into-drawing'));

    testWidgets('🚨pressed, the text in hand is its cel\'s DRAWING: the '
        'canvas shows what it showed, to the byte, the hand is free — and '
        'one undo gives the text back', (tester) async {
      final c = await hiInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final showed = celSurfaceWithTextsLaid(celOf(tester));
      final x = c.dx.toInt() + 2;
      final y = c.dy.toInt() + 2;
      expect(celOf(tester).tiles, isEmpty, reason: '⛔fixture: bare paper');
      expect(shownPixel(showed, x, y)![3], 255, reason: '⛔fixture: its ink');
      await reach(tester, 'into-drawing');
      expect(button(tester).onPressed, isNotNull, reason: 'lit');

      await press(tester, 'into-drawing');

      final cel = celOf(tester);
      expect(cel.texts, isEmpty);
      expect(cel.tiles, isNotEmpty, reason: 'its pixels are the drawing');
      expect(celSurfaceWithTextsLaid(cel), showed);
      expect(canvasShows(tester), showed);
      expect(textToolOf(tester).session, isNull);
      expect(history.undoCount, steps + 1);
      expect(button(tester).onPressed, isNull, reason: 'out again');

      history.undo();
      await pumpFrames(tester);

      expect(celOf(tester).texts.single.content.text, 'hi');
      expect(celOf(tester).tiles, isEmpty);
      expect(celSurfaceWithTextsLaid(celOf(tester)), showed);
    });

    testWidgets('🚨pressed while the text is TYPED INTO, what was typed '
        'lands first — a step of its own — and one undo gives back the '
        'text as it was typed', (tester) async {
      await pumpWithSettings(tester);
      final history = sessionOf(tester).historyManager;
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      final steps = history.undoCount;
      expect(celOf(tester).texts, isEmpty, reason: '⛔fixture: not landed');
      expect(textToolOf(tester).letters, isNotNull, reason: '⛔fixture');

      await press(tester, 'into-drawing');

      expect(celOf(tester).texts, isEmpty);
      expect(celOf(tester).tiles, isNotEmpty);
      expect(textToolOf(tester).session, isNull);
      expect(textField(), findsNothing);
      expect(history.undoCount, steps + 2);

      history.undo();
      await pumpFrames(tester);

      expect(celOf(tester).texts.single.content.text, 'hi');
      expect(celOf(tester).tiles, isEmpty);
    });

    testWidgets('with nothing in hand it is there, and out', (tester) async {
      await pumpWithSettings(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;

      await press(tester, 'into-drawing');

      expect(button(tester).onPressed, isNull);
      expect(history.undoCount, steps);
    });
  });

  group('the list of the cel\'s texts', () {
    /// 「hi」 on the cel, and 「yo」 under it on the canvas — set after, so on
    /// top of the stack — with nothing in hand.
    Future<Offset> twoTexts(WidgetTester tester) async {
      final c = await hiInHand(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      await clickAt(tester, c.dx, c.dy + 120);
      await typeText(tester, 'yo');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(celOf(tester).texts, hasLength(2), reason: '⛔fixture');
      expect(textToolOf(tester).session, isNull, reason: '⛔fixture');
      return c;
    }

    Future<void> openList(WidgetTester tester) async {
      await tester.ensureVisible(row('selected-text'));
      await pumpFrames(tester);
      await tester.tap(row('selected-text'));
      await pumpFrames(tester);
    }

    testWidgets('🚨a text picked in the list is the one in hand ON THE '
        'CANVAS — its box wears the handles', (tester) async {
      await twoTexts(tester);

      await openList(tester);
      // 「hi」 is under 「yo」: second from the top.
      await tester.tapAt(
        tester.getTopLeft(row('text-1')) + const Offset(24, 16),
      );
      await pumpFrames(tester);

      final session = textToolOf(tester).session;
      expect(session, isNotNull);
      expect(session!.content.text, 'hi');
      expect(textToolOf(tester).hold, CelTextHold.box);
      // 「yo」 dashed — two paths — and 「hi」's box; a handle a corner.
      final chrome = tester.renderObject(textChrome());
      expect(chrome, paintsExactlyCountTimes(#drawPath, 2 + 1));
      expect(chrome, paintsExactlyCountTimes(#drawRect, 4 * 2));
    });

    testWidgets('🚨a row\'s delete takes that text off its cel — one step, '
        'and one undo puts it back', (tester) async {
      await twoTexts(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;

      await openList(tester);
      await tester.tap(row('text-0-delete'));
      await pumpFrames(tester);

      expect(
        [for (final text in celOf(tester).texts) text.content.text],
        ['hi'],
      );
      expect(history.undoCount, steps + 1);

      history.undo();
      await pumpFrames(tester);

      expect(
        [for (final text in celOf(tester).texts) text.content.text],
        ['hi', 'yo'],
      );
    });

    testWidgets('🚨a step of history that takes the cel\'s only text away '
        'shuts the list, and the step back opens it', (tester) async {
      await hiInHand(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      PanelFlyoutButton field() =>
          tester.widget<PanelFlyoutButton>(row('selected-text'));
      expect(field().enabled, isTrue, reason: '⛔fixture');
      final history = sessionOf(tester).historyManager;

      history.undo();
      await pumpFrames(tester);

      expect(celOf(tester).texts, isEmpty, reason: '⛔fixture');
      expect(field().enabled, isFalse);

      history.redo();
      await pumpFrames(tester);

      expect(field().enabled, isTrue);
    });

    testWidgets('🚨it follows the FRAME under the playhead: on a frame whose '
        'cel carries no text it is shut, and back on the first it opens', (
      tester,
    ) async {
      await hiInHand(tester, project: textToolProject(drawings: 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      PanelFlyoutButton field() =>
          tester.widget<PanelFlyoutButton>(row('selected-text'));
      expect(field().enabled, isTrue, reason: '⛔fixture');

      sessionOf(tester).selectFrameIndex(1);
      await pumpFrames(tester);

      expect(
        celOf(tester, textToolSecondKey).texts,
        isEmpty,
        reason: '⛔fixture',
      );
      expect(field().enabled, isFalse);

      sessionOf(tester).selectFrameIndex(0);
      await pumpFrames(tester);

      expect(field().enabled, isTrue);
    });
  });

  testWidgets('🚨the box width swaps the text in hand and no pixel of it '
      'moves', (tester) async {
    final c = await hiInHand(tester);
    final before = [
      for (final (x, y) in [(2, 2), (94, 58), (100, 30), (48, 62)])
        shownPixel(
          celOf(tester),
          c.dx.toInt() + x,
          c.dy.toInt() + y,
        ),
    ];

    await press(tester, 'box-width-fixed');

    // 「hi」 is 96 wide, and a box is a pixel past its longest line.
    final boxed = celOf(tester).texts.single.content;
    expect(boxed.wrapWidth, 97);
    expect(boxed.text, 'hi');
    expect([
      for (final (x, y) in [(2, 2), (94, 58), (100, 30), (48, 62)])
        shownPixel(
          celOf(tester),
          c.dx.toInt() + x,
          c.dy.toInt() + y,
        ),
    ], before);
  });
}
