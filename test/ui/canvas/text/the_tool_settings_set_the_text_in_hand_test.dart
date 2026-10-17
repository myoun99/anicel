import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import 'package:anicel/src/ui/brush/text_tool_settings.dart'
    show TextToolSettings;
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart'
    show ToolSettingsSection;
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/brush/tool_setting_rows.dart'
    show ToolSettingAction, ToolSettingChoiceRow, ToolSettingRow;
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/shortcuts/panel_keys.dart' show PanelKeysBinding;
import 'package:anicel/src/ui/text/cel_text_layout.dart' show celTextBoxOf;
import 'package:anicel/src/ui/text/readout_text.dart' show columnValueText;
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart'
    show SettingsSwitchRow;
import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';
import '../../../helpers/frame_census.dart';
import '../../../helpers/tool_setting_action_probe.dart';

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

  /// The box [name] reading [number].
  Finder reading(String name, double number) => find.descendant(
    of: row(name),
    matching: find.text(columnValueText(number)),
  );

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
    expect(landed.paragraphs.single.align, TextCelAlign.center);
  });

  group('the keyboard, while a text is typed into', () {
    final typed = find.byKey(const ValueKey<String>('field-slider-type-input'));

    /// The pencil of the bar [name], brought on screen and pressed.
    Future<void> pencil(WidgetTester tester, String name) async {
      await reach(tester, name);
      await tester.tap(
        find.descendant(
          of: row(name),
          matching: find.byKey(const ValueKey<String>('field-slider-type')),
        ),
      );
      await pumpFrames(tester);
    }

    EditableText typedIn(WidgetTester tester, String name) =>
        tester.widget<EditableText>(
          find.descendant(
            of: find.descendant(of: row(name), matching: typed),
            matching: find.byType(EditableText),
          ),
        );

    bool textHasTheKeyboard(WidgetTester tester) =>
        tester.widget<EditableText>(textField()).focusNode.hasFocus;

    // 🗣️유저 2026-10-14 (F-353): 「텍스트도구로 화면에 클릭해서 캐럿이
    // 생긴상황. 즉 텍스트 편집중인 상황에서 크기쪽 연필누르면 텍스트 선택되지
    // 않은 상태. 추가로 자간같은거 연필누르면 여러 박스가 강조색 되있는상태」.
    testWidgets('🚨F-353: its pencil takes the keyboard, the number '
        'selected — another bar\'s closes it, ONE field open — and the '
        'keyboard goes back to the text when that one closes', (
      tester,
    ) async {
      await pumpWithSettings(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      expect(textHasTheKeyboard(tester), isTrue, reason: '⛔fixture');

      await pencil(tester, 'size');

      final size = typedIn(tester, 'size');
      expect(size.focusNode.hasFocus, isTrue);
      expect(
        size.controller.selection,
        TextSelection(baseOffset: 0, extentOffset: size.controller.text.length),
      );

      // A face arrives in the engine meanwhile: the tool reads its texts
      // again and tells whoever listens — and the keyboard stays put.
      textToolOf(tester).celTextsChanged();
      await pumpFrames(tester);

      expect(typedIn(tester, 'size').focusNode.hasFocus, isTrue);

      await pencil(tester, 'tracking');

      expect(typed, findsOneWidget, reason: 'one field open');
      expect(typedIn(tester, 'tracking').focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);

      expect(typed, findsNothing);
      expect(textToolOf(tester).letters, isNotNull, reason: 'still typing');
      expect(textHasTheKeyboard(tester), isTrue);
    });

    testWidgets('🚨but letters TAKEN UP take the keyboard from whoever holds '
        'it — the person pressed into a text', (tester) async {
      await pumpWithSettings(tester);
      // A field that keeps the keyboard through a press outside it, as a
      // stock one does through a touch.
      final elsewhere = FocusNode();
      final field = OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          top: 0,
          width: 120,
          child: Material(
            child: TextField(focusNode: elsewhere, onTapOutside: (_) {}),
          ),
        ),
      );
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .overlay!
          .insert(field);
      await pumpFrames(tester);
      elsewhere.requestFocus();
      await pumpFrames(tester);
      expect(elsewhere.hasFocus, isTrue, reason: '⛔fixture');

      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);

      expect(textToolOf(tester).letters, isNotNull, reason: '⛔fixture');
      expect(textHasTheKeyboard(tester), isTrue);
      field.remove();
      await pumpFrames(tester);
      elsewhere.dispose();
    });

    testWidgets('🚨and held by NO field — a control took the keyboard — the '
        'text takes it back at its next change', (tester) async {
      await pumpWithSettings(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      final control = FocusNode();
      final entry = OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          top: 0,
          child: Focus(
            focusNode: control,
            child: const SizedBox(width: 8, height: 8),
          ),
        ),
      );
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .overlay!
          .insert(entry);
      await pumpFrames(tester);
      control.requestFocus();
      await pumpFrames(tester);
      expect(textHasTheKeyboard(tester), isFalse, reason: '⛔fixture');

      textToolOf(tester).celTextsChanged();
      await pumpFrames(tester);

      expect(textHasTheKeyboard(tester), isTrue);
      entry.remove();
      await pumpFrames(tester);
      control.dispose();
    });

    testWidgets('🚨with letters SELECTED it reaches those alone — and the '
        'keyboard is the text\'s again once it is set', (tester) async {
      final c = await hiInHand(tester);
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

      await pencil(tester, 'size');
      await tester.enterText(typed, '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);

      expect(typed, findsNothing, reason: '⛔fixture: set');
      expect(textHasTheKeyboard(tester), isTrue);
      expect(
        textToolOf(tester).letters!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      final spans = celOf(tester).texts.single.content.spans;
      expect([for (final span in spans) span.text], ['h', 'i']);
      expect(spans.last.style.fontSize, closeTo(50, 1e-9));
      expect(spans.first.style.fontSize, isNot(closeTo(50, 1e-9)));
    });
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
  group('「래스터라이즈」', () {
    ToolSettingAction button(WidgetTester tester) =>
        tester.toolSettingAction(row('into-drawing'));

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

  // 🗣️유저 2026-10-06: 「세로쓰기: 1차는 가로만」 → 「어차피 타임시트나
  // x시트에서 가로쓰기/세로표기같은거 한거 많으니 그거 통합하면서
  // 진행해도될듯」.
  group('「세로」', () {
    /// Whether the cel shows ink at the canvas pixel ([x], [y]).
    bool inked(WidgetTester tester, double x, double y) {
      final pixel = shownPixel(celOf(tester), x.toInt(), y.toInt());
      return pixel != null && pixel[3] != 0;
    }

    testWidgets('🚨picked with nothing in hand, the NEXT text typed on the '
        'canvas is written in columns: it runs DOWN from where it was '
        'begun, and to its LEFT', (tester) async {
      await pumpWithSettings(tester);
      await press(tester, 'writing-columns');
      final c = canvasPixelInView(tester);

      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'ab');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);

      expect(celOf(tester).texts.single.content.vertical, isTrue);
      // 「ab」 lies down the column: two letters long under the anchor, one
      // column wide to its left — and nothing to its right.
      expect(inked(tester, c.dx - 4, c.dy + 4), isTrue);
      expect(inked(tester, c.dx - 4, c.dy + 80), isTrue);
      expect(inked(tester, c.dx + 4, c.dy + 4), isFalse);
      expect(inked(tester, c.dx - 4, c.dy - 4), isFalse);
    });

    testWidgets('🚨picked with a text in hand, that text is written the '
        'other way where it stands — one step, and one undo writes it '
        'back', (tester) async {
      final c = await hiInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      expect(inked(tester, c.dx + 80, c.dy + 4), isTrue, reason: '⛔fixture');

      await press(tester, 'writing-columns');

      expect(celOf(tester).texts.single.content.vertical, isTrue);
      expect(history.undoCount, steps + 1);
      expect(textToolOf(tester).session, isNotNull, reason: 'in hand');
      // Its block's top left corner is where it was: the letters run down
      // from there, and no longer along the line.
      expect(inked(tester, c.dx + 4, c.dy + 80), isTrue);
      expect(inked(tester, c.dx + 80, c.dy + 4), isFalse);

      history.undo();
      await pumpFrames(tester);

      expect(celOf(tester).texts.single.content.vertical, isFalse);
      expect(inked(tester, c.dx + 80, c.dy + 4), isTrue);
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

  // 🗣️I-95 (유저 2026-10-12): 「텍스트도구에도 변형도구처럼 위치값 존재 …
  // 프리미어처럼 글자 캔버스에서 가로중앙정렬해서 중앙에 넣는다던가」 —
  // I-95-Q1 (10-14): 「개념적으로 트랜스폼이랑 같은 인식임」.
  group('「위치」', () {
    /// The middle of the box of the cel's one text, as it landed.
    Offset landedCentre(WidgetTester tester) =>
        celTextBoxOf(celOf(tester).texts.single.content).centre;

    DragValueLabel box(WidgetTester tester, String name) =>
        tester.widget<DragValueLabel>(
          find.ancestor(of: row(name), matching: find.byType(DragValueLabel)),
        );

    testWidgets('🚨X and Y read where the middle of the box stands — a '
        'number typed stands it there, and a step goes a pixel on: a step '
        'back each, the text still in hand', (tester) async {
      await hiInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final before = landedCentre(tester);
      await reach(tester, 'x');

      expect(reading('x', before.dx), findsOneWidget);
      expect(reading('y', before.dy), findsOneWidget);

      await tester.tap(row('x-edit'));
      await pumpFrames(tester);
      await tester.enterText(row('x-input'), '500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);

      expect(
        landedCentre(tester),
        offsetMoreOrLessEquals(Offset(500, before.dy)),
      );
      expect(reading('x', 500), findsOneWidget);
      expect(history.undoCount, steps + 1);
      expect(textToolOf(tester).session, isNotNull, reason: 'in hand');

      await press(tester, 'x-step-up');

      expect(
        landedCentre(tester),
        offsetMoreOrLessEquals(Offset(501, before.dy)),
      );
      expect(history.undoCount, steps + 2);

      // 🗣️F-377: undo takes the box's steps back one at a time while the
      // text is held — by the rail's ↶, a door undo is asked through as
      // Ctrl+Z is (H42). ↩️History's own undo stood in for it: a hold is
      // let go of — its steps ONE — before the document is undone.
      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await pumpFrames(tester);

      expect(landedCentre(tester).dx, moreOrLessEquals(500));
      expect(textToolOf(tester).session, isNotNull, reason: 'in hand');

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await pumpFrames(tester);

      expect(landedCentre(tester), offsetMoreOrLessEquals(before));
      expect(textToolOf(tester).session, isNotNull, reason: 'in hand');
      expect(history.undoCount, steps);
    });

    testWidgets('🚨a scrub on X carries the text a whole pixel at a time and '
        'lands nothing as it goes — and is ONE step back', (tester) async {
      await hiInHand(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final before = landedCentre(tester);
      await reach(tester, 'x');

      // ⚠️A hand-driven gesture, not `tester.drag`: that delivers the whole
      // travel as ONE update, and would pass on a box that landed each.
      final scrub = await tester.startGesture(
        tester.getCenter(row('x')),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 4; i += 1) {
        await scrub.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      final carried =
          textToolOf(tester).session!.shown.layout.onCanvas.centre - before;

      expect(carried.dx, greaterThan(0), reason: '⛔전제: it was carried');
      expect(carried.dx, moreOrLessEquals(carried.dx.roundToDouble()));
      expect(carried.dy, moreOrLessEquals(0));
      expect(history.undoCount, steps, reason: 'nothing landed as it went');

      await scrub.up();
      await pumpFrames(tester);

      expect(landedCentre(tester), offsetMoreOrLessEquals(before + carried));
      expect(history.undoCount, steps + 1);

      history.undo();
      await pumpFrames(tester);

      expect(landedCentre(tester), offsetMoreOrLessEquals(before));
    });

    testWidgets('가로 가운데 · 세로 가운데 stand it on the canvas\'s middle '
        'lines, a step each — and with nothing in hand all of 「위치」 keeps '
        'its place, dimmed', (tester) async {
      await pumpWithSettings(tester);
      await reach(tester, 'x');

      for (final name in ['x', 'y']) {
        expect(box(tester, name).enabled, isFalse, reason: name);
      }
      for (final name in ['centre-across', 'centre-down']) {
        expect(
          tester.toolSettingAction(row(name)).onPressed,
          isNull,
          reason: name,
        );
      }

      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      final history = sessionOf(tester).historyManager;
      final steps = history.undoCount;
      final before = landedCentre(tester);
      final middle = Offset(
        defaultCutCanvasSize.width / 2,
        defaultCutCanvasSize.height / 2,
      );
      for (final (stands, middleOf) in [
        (before.dx, middle.dx),
        (before.dy, middle.dy),
      ]) {
        expect(stands, isNot(moreOrLessEquals(middleOf)), reason: '⛔fixture');
      }

      await press(tester, 'centre-across');

      expect(
        landedCentre(tester),
        offsetMoreOrLessEquals(Offset(middle.dx, before.dy)),
      );

      await press(tester, 'centre-down');

      expect(landedCentre(tester), offsetMoreOrLessEquals(middle));
      expect(history.undoCount, steps + 2);
    });
  });

  // 🚨text-settings-redrawn-per-drag-sample (10-14): the hand tells of every
  // sample of a drag, and the settings were ONE builder on it — every row
  // was built again for each. A control hears only what it shows (F-164,
  // the transform tool's numbers: 「패널리빌드하지말고 글자만 바꾸게」).
  group('one sample of a drag on the canvas', () {
    /// What no sample of a drag of the text in hand builds again: the
    /// section, its rows and keys, and every control whose value such a
    /// drag does not move.
    const steady = [
      TextToolSettings,
      ToolSettingsSection,
      PanelKeysBinding,
      ToolSettingRow,
      SettingsSwitchRow,
      ToolSettingChoiceRow<bool>,
      ToolSettingChoiceRow<TextCelAlign>,
      ColorSwatchButton,
      PanelFlyoutButton,
    ];

    /// The mouse, event by event: the census is of ONE sample, and the
    /// harness's gestures pump between theirs.
    const mouse = 41;
    PointerDownEvent downAt(Offset at) => PointerDownEvent(
      pointer: mouse,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
      position: at,
    );
    PointerMoveEvent moveTo(Offset at) => PointerMoveEvent(
      pointer: mouse,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
      position: at,
    );

    /// A drag on the screen from [from] by [first] and then [then], the
    /// census taken of the second sample alone — [meanwhile] asked before
    /// the mouse lets go.
    Future<List<Type>> dragged(
      WidgetTester tester,
      Offset from, {
      required Offset first,
      required Offset then,
      required void Function() meanwhile,
    }) async {
      final binding = tester.binding;
      binding.handlePointerEvent(downAt(from));
      await tester.pump();
      binding.handlePointerEvent(moveTo(from + first));
      await tester.pump();
      final census = await frameCensus(
        tester,
        () => binding.handlePointerEvent(moveTo(from + first + then)),
      );
      meanwhile();
      binding.handlePointerEvent(
        PointerUpEvent(
          pointer: mouse,
          kind: PointerDeviceKind.mouse,
          position: from + first + then,
        ),
      );
      await pumpFrames(tester);
      return census.rebuilt;
    }

    Offset shownCentre(WidgetTester tester) =>
        textToolOf(tester).session!.shown.layout.onCanvas.centre;

    testWidgets('🚨the text CARRIED builds its X again — and nothing else of '
        'the settings, not even its Y', (tester) async {
      final c = await hiInHand(tester);
      await reach(tester, 'x');
      final before = shownCentre(tester);

      final rebuilt = await dragged(
        tester,
        onScreen(tester, c.dx + 10, c.dy + 30),
        first: const Offset(20, 0),
        then: const Offset(20, 0),
        meanwhile: () {
          final centre = shownCentre(tester);
          expect(centre.dx, greaterThan(before.dx), reason: '⛔fixture');
          expect(reading('x', centre.dx), findsOneWidget, reason: 'LIVENESS');
        },
      );

      expect(
        rebuilt.where((type) => type == DragValueLabel),
        hasLength(1),
        reason: 'the X — and not the Y, which stood still',
      );
      for (final type in [...steady, FieldSlider]) {
        expect(rebuilt, isNot(contains(type)), reason: '$type');
      }
    });

    testWidgets('🚨the text SIZED by a corner builds its size again — and no '
        'row, switch, choice, colour or list of the settings', (tester) async {
      await hiInHand(tester);
      await reach(tester, 'size');
      final before = textToolOf(tester).contentInHand!.spans.single.style;
      final corner = textToolOf(tester).session!.shown.layout.onCanvas.corners
          .reduce((a, b) => a.dx + a.dy > b.dx + b.dy ? a : b);

      final rebuilt = await dragged(
        tester,
        onScreen(tester, corner.dx, corner.dy),
        first: const Offset(10, 10),
        then: const Offset(20, 20),
        meanwhile: () {
          final sized = textToolOf(tester).contentInHand!.spans.single.style;
          expect(
            sized.fontSize,
            isNot(before.fontSize),
            reason: '⛔fixture: the corner sizes it',
          );
          expect(
            tester.widget<FieldSlider>(row('size')).value,
            sized.fontSize,
            reason: 'LIVENESS',
          );
        },
      );

      expect(rebuilt, contains(FieldSlider));
      for (final type in steady) {
        expect(rebuilt, isNot(contains(type)), reason: '$type');
      }
    });

    testWidgets('🚨letters SWEPT OVER that agree on everything build nothing '
        'of the settings again', (tester) async {
      final c = await hiInHand(tester);
      // Into the letters — a click inside the box, beside the cross in its
      // middle.
      await clickAt(tester, c.dx + 20, c.dy + 12);
      expect(textToolOf(tester).hold, CelTextHold.letters, reason: '⛔fixture');
      Offset along(double pixels) =>
          onLayer(tester, pixels, 0) - onLayer(tester, 0, 0);

      final rebuilt = await dragged(
        tester,
        onScreen(tester, c.dx + 5, c.dy + 30),
        first: along(40),
        then: along(45),
        meanwhile: () => expect(
          textToolOf(tester).letters!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 2),
          reason: 'LIVENESS: the letters were swept over',
        ),
      );

      for (final type in [...steady, FieldSlider, DragValueLabel]) {
        expect(rebuilt, isNot(contains(type)), reason: '$type');
      }
    });
  });
}
