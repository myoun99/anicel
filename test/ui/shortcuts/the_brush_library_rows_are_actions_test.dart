// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든 모든
// 버튼」; asked how far (I-40-Q1, 10-08): the editing screen's command
// buttons and menu rows.
//
// THE BRUSH LIBRARY'S ⋯ AND THE TWO BUTTONS BESIDE IT ARE ACTIONS, AND A KEY
// PRESSES THE LIBRARY OF THE TOOL IN HAND — its menu as that panel opens it,
// its buttons as it shows them. A hand holding a tool whose library is not
// on screen presses nothing: there is no row or button of it to press.
import 'package:file_selector/file_selector.dart' show XFile, XTypeGroup;
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show FileSelectorPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/panel_keys.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/app_icon_button_probe.dart';

const k = LogicalKeyboardKey.keyK;

const _ink = BrushGroupId('ink');

final _pen = BrushPreset(
  id: const BrushPresetId('pen'),
  name: 'Pen',
  settings: BrushSettings(size: 4),
  groupId: _ink,
);

final _soft = BrushPreset(
  id: const BrushPresetId('soft'),
  name: 'Soft',
  settings: BrushSettings(size: 30),
);

/// A library panel at its fullest — every verb wired, a group open and a
/// brush held — as [tool]'s.
Widget libraryPanel({
  CanvasTool tool = CanvasTool.brush,
  Key? key,
  VoidCallback? onSave,
  VoidCallback? onImport,
}) => BrushPresetPanel(
  key: key,
  tool: tool,
  presets: [_pen, _soft],
  groups: const [BrushGroup(id: _ink, name: 'Ink')],
  selectedPresetId: _pen.id,
  onPresetApplied: (_) {},
  onPresetSaveRequested: onSave ?? () {},
  onPresetDeleted: (_) {},
  onPresetImportRequested: onImport ?? () {},
  onPresetRenamed: (_, _) {},
  onGroupCreated: (_) {},
  onGroupEdited: (_, _, _) {},
  onGroupDeleted: (_) {},
  onLibraryReset: () {},
  onPresetExported: (_) {},
  onGroupExported: (_) {},
);

/// [panels] side by side, binding to [keys] as the shell's panels do.
Future<void> pumpPanels(
  WidgetTester tester,
  PanelKeys keys,
  List<Widget> panels,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: PanelKeysScope(
        keys: keys,
        child: Scaffold(
          body: Row(
            children: [
              for (final panel in panels)
                SizedBox(width: 300, height: 600, child: panel),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpHome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const HomePage()),
  );
  await tester.pumpAndSettle();
}

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

Future<void> takeUp(WidgetTester tester, String tool) async {
  await tester.tap(find.byKey(ValueKey<String>('tool-$tool-button')));
  await tester.pumpAndSettle();
}

/// [tool]'s library panel, on stage or kept off it.
BrushPresetPanel panelOf(WidgetTester tester, CanvasTool tool) =>
    tester.widget<BrushPresetPanel>(
      find.byWidgetPredicate(
        (widget) => widget is BrushPresetPanel && widget.tool == tool,
        skipOffstage: false,
      ),
    );

Set<BrushPresetId> presetsOf(WidgetTester tester) => {
  for (final preset in panelOf(tester, CanvasTool.brush).presets) preset.id,
};

void main() {
  setUp(() => _held = null);

  group('the registry', () {
    testWidgets('🚨every row the ⋯ can open names one action of the '
        'registry, and every menu action of the library has its row', (
      tester,
    ) async {
      final keys = PanelKeys();
      await pumpPanels(tester, keys, [libraryPanel()]);

      final registry = {
        for (final definition in editorActionDefinitions) definition.id,
      };
      final rows = keys.menuRows(CanvasTool.brush).toList();
      expect(rows, hasLength(13), reason: '⛔premise: the rows');
      for (final row in rows) {
        expect(row.shortcuts, hasLength(1), reason: row.keyValue);
        expect(registry, contains(row.shortcuts.single), reason: row.keyValue);
      }
      expect(
        {
          for (final definition in editorActionDefinitions)
            if (definition.category == 'Brush Library' && definition.menuRow)
              definition.id,
        },
        {for (final row in rows) row.shortcuts.single},
      );
    });

    testWidgets('the two buttons beside the ⋯ name the library\'s other '
        'two', (tester) async {
      final keys = PanelKeys();
      await pumpPanels(tester, keys, [libraryPanel()]);

      List<String> shortcutsOf(String keyValue) => tester
          .appIconButton(find.byKey(ValueKey<String>(keyValue)))
          .shortcuts;
      expect(shortcutsOf('brush-preset-import-button'), [
        BrushLibraryActionIds.importBrushes,
      ]);
      expect(shortcutsOf('brush-preset-save-button'), [
        BrushLibraryActionIds.saveHeldBrush,
      ]);
      expect(
        {
          for (final definition in editorActionDefinitions)
            if (definition.category == 'Brush Library' && !definition.menuRow)
              definition.id,
        },
        {BrushLibraryActionIds.importBrushes, BrushLibraryActionIds.saveHeldBrush},
      );
    });

    test('they stand under the library\'s own category, and none ships '
        'with a key — nobody named one', () {
      final library = [
        for (final definition in editorActionDefinitions)
          if (definition.category == 'Brush Library') definition,
      ];
      expect(library, hasLength(15));
      for (final definition in library) {
        expect(definition.defaultActivators, isEmpty, reason: definition.id);
      }
      expect(
        AppStrings.of(AppLanguage.ko).shortcutCategory('Brush Library', ''),
        '브러시 라이브러리',
      );
    });

    test('a row is named by its own words where they say what it does, and '
        'with its menu first where they need one', () {
      expect(editorActionLabel(BrushLibraryActionIds.newGroup), 'New group');
      expect(
        editorActionLabel(BrushLibraryActionIds.deleteBrush),
        'Delete selected brush',
      );
      expect(
        editorActionLabel(BrushLibraryActionIds.name),
        'Brush options: Name',
      );
      expect(
        editorActionLabel(BrushLibraryActionIds.saveHeldBrush),
        'Save current settings as preset',
      );
    });

    test('…in the program\'s language', () {
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      expect(
        editorActionLabel(BrushLibraryActionIds.folderName),
        '브러시 옵션: 폴더 이름',
      );
      expect(
        editorActionLabel(BrushLibraryActionIds.reset),
        '브러시 라이브러리 초기화',
      );
    });
  });

  group('each panel is its own tool\'s', () {
    testWidgets('two libraries on screen: a press reaches the one of the '
        'tool it names, and its menu is that panel\'s', (tester) async {
      final keys = PanelKeys();
      final saved = <CanvasTool>[];
      await pumpPanels(tester, keys, [
        libraryPanel(onSave: () => saved.add(CanvasTool.brush)),
        libraryPanel(
          tool: CanvasTool.eraser,
          onSave: () => saved.add(CanvasTool.eraser),
        ),
      ]);

      keys.press(BrushLibraryActionIds.saveHeldBrush, CanvasTool.eraser);
      expect(saved, [CanvasTool.eraser]);
      keys.press(BrushLibraryActionIds.saveHeldBrush, CanvasTool.brush);
      expect(saved, [CanvasTool.eraser, CanvasTool.brush]);
      expect(
        keys.menuRows(CanvasTool.select),
        isEmpty,
        reason: 'no library of the select tool is mounted',
      );
    });

    testWidgets('a panel that goes takes its presses with it — and only '
        'its own: one mounted in its place keeps answering', (tester) async {
      final keys = PanelKeys();
      final imported = <String>[];
      await pumpPanels(tester, keys, [
        libraryPanel(
          key: const ValueKey<String>('first'),
          onImport: () => imported.add('first'),
        ),
      ]);
      // The first's State goes as the second's comes: the second binds in
      // its initState, before the first's dispose.
      await pumpPanels(tester, keys, [
        libraryPanel(
          key: const ValueKey<String>('second'),
          onImport: () => imported.add('second'),
        ),
      ]);

      keys.press(BrushLibraryActionIds.importBrushes, CanvasTool.brush);
      expect(imported, ['second']);

      await pumpPanels(tester, keys, []);
      keys.press(BrushLibraryActionIds.importBrushes, CanvasTool.brush);
      expect(imported, ['second'], reason: 'no panel, nothing pressed');
      expect(keys.menuRows(CanvasTool.brush), isEmpty);
    });

    testWidgets('a panel built again for another tool is that tool\'s from '
        'then on', (tester) async {
      final keys = PanelKeys();
      final saved = <String>[];
      Widget panel(CanvasTool tool) => libraryPanel(
        tool: tool,
        key: const ValueKey<String>('one'),
        onSave: () => saved.add(tool.name),
      );
      await pumpPanels(tester, keys, [panel(CanvasTool.brush)]);
      await pumpPanels(tester, keys, [panel(CanvasTool.eraser)]);

      keys.press(BrushLibraryActionIds.saveHeldBrush, CanvasTool.brush);
      expect(saved, isEmpty, reason: 'the brush tool has no panel now');
      keys.press(BrushLibraryActionIds.saveHeldBrush, CanvasTool.eraser);
      expect(saved, ['eraser']);
    });
  });

  group('a key presses the library of the tool in hand', () {
    testWidgets('a view row: the brush tool\'s library hides its stroke '
        'previews, and shows them again — and with the select tool in hand, '
        'whose library is not on screen, nothing', (tester) async {
      await pumpHome(tester);
      bool strokes() =>
          panelOf(tester, CanvasTool.brush).viewOptions.showStrokePreview;
      expect(strokes(), isTrue, reason: 'premise: on by default');

      await pressKeyOf(tester, BrushLibraryActionIds.strokePreview);
      expect(strokes(), isFalse);
      await pressKeyOf(tester, BrushLibraryActionIds.strokePreview);
      expect(strokes(), isTrue);

      await takeUp(tester, 'select');
      await pressKeyOf(tester, BrushLibraryActionIds.strokePreview);
      await takeUp(tester, 'brush');
      expect(strokes(), isTrue);
    });

    testWidgets('the save button: the brush in hand is saved as a preset — '
        'and with the select tool in hand, nothing is', (tester) async {
      await pumpHome(tester);
      final before = presetsOf(tester);

      await pressKeyOf(tester, BrushLibraryActionIds.saveHeldBrush);
      final saved = presetsOf(tester).difference(before);
      expect(saved, hasLength(1));
      expect(panelOf(tester, CanvasTool.brush).selectedPresetId, saved.single);

      await takeUp(tester, 'select');
      await pressKeyOf(tester, BrushLibraryActionIds.saveHeldBrush);
      expect(presetsOf(tester), {...before, ...saved});
    });

    testWidgets('the import button: the file window opens, once a press — '
        'and with the select tool in hand, not at all', (tester) async {
      final real = FileSelectorPlatform.instance;
      final windows = _CountingFileWindow();
      FileSelectorPlatform.instance = windows;
      addTearDown(() => FileSelectorPlatform.instance = real);
      await pumpHome(tester);

      await pressKeyOf(tester, BrushLibraryActionIds.importBrushes);
      expect(windows.opened, 1);

      await takeUp(tester, 'select');
      await pressKeyOf(tester, BrushLibraryActionIds.importBrushes);
      expect(windows.opened, 1);
    });

    testWidgets('🚨the eraser in hand: ITS library — the delete row deletes '
        'the brush the eraser holds, and the brush tool\'s stays', (
      tester,
    ) async {
      await pumpHome(tester);
      await pressKeyOf(tester, BrushLibraryActionIds.saveHeldBrush);
      final brushHolds = panelOf(tester, CanvasTool.brush).selectedPresetId!;
      // A saved brush's id is the clock's millisecond — two saves in one
      // would be one id.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await takeUp(tester, 'eraser');
      await pressKeyOf(tester, BrushLibraryActionIds.saveHeldBrush);
      final eraserHolds = panelOf(tester, CanvasTool.eraser).selectedPresetId!;
      expect(eraserHolds, isNot(brushHolds), reason: 'premise');

      await pressKeyOf(tester, BrushLibraryActionIds.deleteBrush);

      expect(presetsOf(tester), contains(brushHolds));
      expect(presetsOf(tester), isNot(contains(eraserHolds)));
    });
  });
}

/// A file window that opens, counts, and is cancelled.
class _CountingFileWindow extends FileSelectorPlatform {
  int opened = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opened += 1;
    return null;
  }
}
