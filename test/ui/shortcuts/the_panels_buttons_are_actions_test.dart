// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든 모든
// 버튼」; asked how far (I-40-Q1, 10-08): the editing screen's command
// buttons and menu rows.
//
// A PANEL'S OWN BUTTONS ARE ACTIONS, AND A KEY PRESSES THE BUTTON — the
// callback it holds, on a panel a key reaches: the panels of the tool in
// hand (the guide list, the text tool's settings) and the panels of no tool
// (the media pool, the timesheet). A dead button is dead by key too.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker;
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/panel_keys.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/cel_text_tool_harness.dart';

const k = LogicalKeyboardKey.keyK;

const panelButtons = [
  EditorActionIds.guideAddSymmetry,
  EditorActionIds.guideAddPerspective,
  EditorActionIds.textDeleteText,
  EditorActionIds.mediaPoolImport,
  EditorActionIds.timesheetFormat,
  EditorActionIds.timesheetDataMode,
];

EditorShortcutBindings bindings(WidgetTester tester) =>
    EditorShortcutScope.peek(tester.element(find.byType(EditorWorkspace)))!;

/// The action [pressKeyOf] last recorded [k] for.
String? _held;

/// Records [k] for [actionId] — alone — and presses it.
Future<void> pressKeyOf(WidgetTester tester, String actionId) async {
  if (_held case final before? when before != actionId) {
    bindings(tester).resetAction(before);
  }
  _held = actionId;
  bindings(tester).setActivators(actionId, const [SingleActivator(k)]);
  await tester.pump();
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

Future<void> pumpHome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const HomePage()),
  );
  await tester.pumpAndSettle();
}

Future<void> takeUp(WidgetTester tester, String tool) async {
  await tester.tap(find.byKey(ValueKey<String>('tool-$tool-button')));
  await tester.pumpAndSettle();
}

/// Opens the rail group [slot] on that side — a panel that ships shut is
/// not mounted, and a key presses only a button a panel shows.
Future<void> openRailGroup(
  WidgetTester tester, {
  required bool right,
  required int slot,
}) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>(
        'rail-group-${EditorWorkspace.railGroupId(right: right, slot: slot)}',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _held = null);

  group('PanelKeys', () {
    test('a panel of no tool answers whatever is in hand; a tool\'s panel '
        'answers only with its tool in hand', () {
      final keys = PanelKeys();
      final pressed = <String>[];
      keys.bind(Object(), (buttons: {'a': () => pressed.add('pool')}, menu: null));
      keys.bind(
        Object(),
        (buttons: {'b': () => pressed.add('guides')}, menu: null),
        tool: CanvasTool.guide,
      );

      keys.press('a', CanvasTool.brush);
      keys.press('b', CanvasTool.brush);
      expect(pressed, ['pool']);
      keys.press('b', CanvasTool.guide);
      expect(pressed, ['pool', 'guides']);
    });

    test('a dead button presses nothing — and an owner let go takes only '
        'its own presses', () {
      final keys = PanelKeys();
      final pressed = <String>[];
      final one = Object();
      final two = Object();
      keys.bind(one, (buttons: {'a': null}, menu: null));
      keys.bind(two, (buttons: {'b': () => pressed.add('two')}, menu: null));

      keys.press('a', CanvasTool.brush);
      expect(pressed, isEmpty);
      keys.unbind(one);
      keys.press('b', CanvasTool.brush);
      expect(pressed, ['two']);
    });
  });

  group('the registry', () {
    test('they are panel buttons, and none ships with a key — nobody named '
        'one', () {
      for (final id in panelButtons) {
        final definition = editorActionDefinitions.singleWhere(
          (definition) => definition.id == id,
        );
        expect(definition.panelButton, isTrue, reason: id);
        expect(definition.menuRow, isFalse, reason: id);
        expect(definition.defaultActivators, isEmpty, reason: id);
      }
    });

    test('…named in the program\'s language — the window\'s own word where '
        'the button opens one', () {
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      expect(
        editorActionLabel(EditorActionIds.guideAddSymmetry),
        '대칭 가이드 추가',
      );
      expect(editorActionLabel(EditorActionIds.mediaPoolImport), '임포트…');
      expect(editorActionLabel(EditorActionIds.timesheetFormat), '타임시트 서식…');
      expect(
        editorActionLabel(EditorActionIds.timesheetDataMode),
        '표기 시트 / 데이터 시트',
      );
      expect(editorActionLabel(EditorActionIds.textDeleteText), '텍스트 삭제');
    });
  });

  group('a key presses the panel\'s button', () {
    testWidgets('the guide list\'s ＋: with the guide tool in hand a symmetry '
        'guide is added — and with the brush in hand, the list kept off '
        'stage adds none', (tester) async {
      await pumpHome(tester);
      await takeUp(tester, 'guide');
      int symmetries() => tester
          .widget<GuideLibraryList>(
            find.byType(GuideLibraryList, skipOffstage: false),
          )
          .guides
          .symmetryGuides
          .length;
      final before = symmetries();

      await pressKeyOf(tester, EditorActionIds.guideAddSymmetry);
      expect(symmetries(), before + 1);

      await takeUp(tester, 'brush');
      await pressKeyOf(tester, EditorActionIds.guideAddSymmetry);
      expect(symmetries(), before + 1);
    });

    testWidgets('the timesheet\'s format window opens by key, and its '
        'notation ⇄ data switch flips — and back', (tester) async {
      await pumpHome(tester);
      final window = find.byKey(
        const ValueKey<String>('timesheet-format-window'),
      );
      expect(window, findsNothing, reason: '⛔premise');
      await pressKeyOf(tester, EditorActionIds.timesheetFormat);
      expect(window, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      bool dataSheet() => tester
          .appIconButton(
            find.byKey(
              const ValueKey<String>('timesheet-data-mode-toggle-button'),
            ),
          )
          .isSelected;
      final before = dataSheet();
      await pressKeyOf(tester, EditorActionIds.timesheetDataMode);
      expect(dataSheet(), !before);
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(dataSheet(), before);
    });

    testWidgets('the media pool\'s ＋ asks for files — whatever tool is in '
        'hand', (tester) async {
      var asked = 0;
      FolderPicker.debugFilePicker =
          ({required acceptedTypeGroups, required allowMultiple}) async {
            asked += 1;
            return const [FolderGrant.cancelled()];
          };
      await pumpHome(tester);
      await pressKeyOf(tester, EditorActionIds.mediaPoolImport);
      expect(asked, 0, reason: 'the pool ships shut: no ＋ to press');

      await openRailGroup(tester, right: true, slot: 3);
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(asked, 1);
      await takeUp(tester, 'select');
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(asked, 2);
    });

    testWidgets('the text tool\'s 🗑 takes the text in hand off its cel — '
        'and with no text in hand, the dead button presses nothing', (
      tester,
    ) async {
      await pumpTextToolApp(tester);
      // The tool's settings ship shut — their 🗑 is not on screen.
      await openRailGroup(tester, right: false, slot: 2);
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      // Esc lets go of the LETTERS — the keyboard is the shortcuts' again —
      // and the text stays in hand by its box.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(textToolOf(tester).contentInHand, isNotNull, reason: '⛔premise');

      await pressKeyOf(tester, EditorActionIds.textDeleteText);
      expect(textToolOf(tester).contentInHand, isNull);
      expect(celOf(tester).texts, isEmpty);

      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
