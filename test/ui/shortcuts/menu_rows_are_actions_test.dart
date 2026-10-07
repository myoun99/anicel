// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록. 타임라인
// 버튼같은거나. 설정의 패널 열기 닫기같은거든 뭐든 모든 버튼」.
//
// THE TOP STRIP'S MENU ROWS ARE ACTIONS, AND A KEY PRESSES THE ROW: every row
// of the project and settings menus that runs something names an action of
// the shortcut list, every such action has its row, and a key recorded for
// one does what the row does — only where the row can be pressed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/panels/workspace_panels_menu.dart';
import 'package:anicel/src/ui/shortcuts/brush_actions.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/panel_actions.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/project_scratch_folder.dart';

const k = LogicalKeyboardKey.keyK;

Future<void> pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const AnicelApp());
  await tester.pumpAndSettle();
}

EditorTopStrip strip(WidgetTester tester) =>
    tester.widget<EditorTopStrip>(find.byType(EditorTopStrip));

BuildContext stripContext(WidgetTester tester) =>
    tester.element(find.byType(EditorTopStrip));

EditorShortcutBindings keys(WidgetTester tester) =>
    EditorShortcutScope.peek(stripContext(tester))!;

/// Records [k] for [actionId] and presses it, once the app has taken the
/// recording in.
Future<void> pressKeyOf(WidgetTester tester, String actionId) async {
  keys(tester).setActivators(actionId, const [SingleActivator(k)]);
  await tester.pump();
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

/// The STRIP's menu rows among the registry's: every menu row but the
/// timeline bar's, which `timeline_bar_rows_are_actions_test.dart` speaks
/// for.
List<EditorActionDefinition> get menuActions => [
  for (final definition in editorActionDefinitions)
    if (definition.menuRow && definition.category != 'Timeline')
      definition,
];

void main() {
  group('the registry', () {
    test('holds the strip\'s menu rows: the project menu\'s in its order '
        'under File, and the settings menu\'s after everything else', () {
      expect(
        [
          for (final definition in editorActionDefinitions)
            if (definition.category == 'File') definition.id,
        ],
        [
          EditorActionIds.fileNew,
          EditorActionIds.fileOpen,
          EditorActionIds.fileSave,
          EditorActionIds.fileSaveAs,
          EditorActionIds.fileBackUpFailedCopy,
          EditorActionIds.fileImport,
          EditorActionIds.fileExport,
        ],
      );
      expect(menuActions, hasLength(19));
      expect(
        editorActionDefinitions.last.category,
        panelActionCategory,
        reason: 'the workspace\'s panels follow, under the same heading',
      );
      // Each of these categories is ONE run of the list — the window prints
      // a heading wherever the category changes.
      final runs = <String>[];
      for (final definition in editorActionDefinitions) {
        if (runs.isEmpty || runs.last != definition.category) {
          runs.add(definition.category);
        }
      }
      for (final category in const ['File', 'Settings', 'Debug', 'Panels']) {
        expect(
          runs.where((run) => run == category),
          hasLength(1),
          reason: '$category in $runs',
        );
      }
    });

    test('only the two saves ship with a key — nobody named another', () {
      expect(
        [
          for (final definition in menuActions)
            if (definition.defaultActivators.isNotEmpty) definition.id,
        ],
        [EditorActionIds.fileSave, EditorActionIds.fileSaveAs],
      );
    });

    test('⛔no registry action reads as a panel\'s row', () {
      expect(
        editorActionDefinitions.where((row) => isPanelActionId(row.id)),
        isEmpty,
      );
      expect(isPanelActionId(panelActionId('timesheet')), isTrue);
      expect(isBrushActionId(panelActionId('timesheet')), isFalse);
    });

    test('the three new categories have a word in every language', () {
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.en) {
          continue;
        }
        for (final category in const ['Settings', 'Debug', 'Panels']) {
          expect(
            AppStrings.of(language).shortcutCategory(category, ''),
            isNotEmpty,
            reason: '${language.name} · $category',
          );
        }
      }
    });
  });

  group('the panels as rows', () {
    const entries = <WorkspacePanelEntry>[
      (tabId: 'timesheet', label: 'Timesheet', visible: true),
      (tabId: 'media', label: 'Media', visible: false),
    ];

    test('are one row per panel, in the list\'s order, each its menu row', () {
      final rows = panelActionsOf(entries);
      expect(rows.map((row) => row.id), ['panel-timesheet', 'panel-media']);
      expect(rows.map((row) => row.label), ['Timesheet', 'Media']);
      for (final row in rows) {
        expect(row.menuRow, isTrue);
        expect(row.category, panelActionCategory);
        expect(row.defaultActivators, isEmpty);
      }
    });

    test('stand after the registry\'s rows and before the brushes\', and a '
        'panel shown or hidden tells nobody', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      var told = 0;
      bindings.addListener(() => told += 1);

      // The brushes first, so the order below is the list's and not the
      // order they were told in.
      bindings.setBrushActions(
        brushActionsOf(const [
          BrushGroup(id: BrushGroupId('inks'), name: 'Inks'),
        ], const []),
      );
      told = 0;
      bindings.setPanelActions(panelActionsOf(entries));
      expect(told, 1);
      expect(
        bindings.definitions
            .skip(editorActionDefinitions.length)
            .map((row) => row.id),
        ['panel-timesheet', 'panel-media', 'brush-group-inks'],
      );

      bindings.setPanelActions(
        panelActionsOf([
          for (final entry in entries)
            (tabId: entry.tabId, label: entry.label, visible: !entry.visible),
        ]),
      );
      expect(told, 1);

      bindings.setPanelActions(
        panelActionsOf([
          for (final entry in entries)
            (tabId: entry.tabId, label: '${entry.label}!', visible: true),
        ]),
      );
      expect(told, 2, reason: 'another language\'s names are other rows');
    });

    test('🚨a panel\'s key is read back BEFORE the workspace has told of its '
        'panels', () async {
      final directory = await Directory.systemTemp.createTemp('panel-keys');
      deleteAfterSessionEnds(directory);
      final path = '${directory.path}/overrides.json';
      File(path).writeAsStringSync(
        '{"version":2,"preset":"anicel","overrides":{"anicel":'
        '{"panel-timesheet":[{"key":${k.keyId}}],'
        '"neither-a-panel-nor-a-brush":[{"key":${k.keyId}}]}}}',
      );
      final bindings = EditorShortcutBindings(
        store: ShortcutSettingsStore(filePath: path),
      );
      addTearDown(bindings.dispose);
      await bindings.restore();
      expect(bindings.isOverridden('panel-timesheet'), isTrue);
      expect(bindings.isOverridden('neither-a-panel-nor-a-brush'), isFalse);

      bindings.setPanelActions(panelActionsOf(entries));
      expect(
        bindings.activatorsFor('panel-timesheet').single.trigger,
        k,
      );
    });
  });

  group('a key and its menu row', () {
    final pressed = <String>[];
    List<PanelFlyoutEntry> menu() => [
      PanelFlyoutItem(
        keyValue: 'open',
        label: 'Open',
        shortcuts: const ['open'],
        onSelected: () => pressed.add('open'),
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'dim',
        label: 'Dim',
        shortcuts: const ['dim'],
        enabled: false,
        onSelected: () => pressed.add('dim'),
      ),
      PanelFlyoutItem(
        keyValue: 'more',
        label: 'More',
        submenuBuilder: () => [
          PanelFlyoutItem(
            keyValue: 'under',
            label: 'Under',
            shortcuts: const ['under'],
            onSelected: () => pressed.add('under'),
          ),
        ],
      ),
    ];
    setUp(pressed.clear);

    test('the rows are the menu\'s, a second level\'s after the row that '
        'opens it', () {
      expect(flyoutRowsOf(menu()).map((row) => row.keyValue), [
        'open',
        'dim',
        'more',
        'under',
      ]);
    });

    test('a key runs the row that names its action — one level down too', () {
      pressFlyoutRow(flyoutRowsOf(menu()), 'open');
      pressFlyoutRow(flyoutRowsOf(menu()), 'under');
      expect(pressed, ['open', 'under']);
    });

    test('⛔a row the menu would not let be pressed is not pressed by key, '
        'and an action no row names presses nothing', () {
      pressFlyoutRow(flyoutRowsOf(menu()), 'dim');
      pressFlyoutRow(flyoutRowsOf(menu()), 'no-such-action');
      expect(pressed, isEmpty);
    });
  });

  group('the shortcut window', () {
    testWidgets('lists the panels under ONE heading: the three of the '
        'registry, then the workspace\'s', (tester) async {
      final bindings = EditorShortcutBindings()
        ..setPanelActions(
          panelActionsOf(const [
            (tabId: 'timesheet', label: 'Timesheet', visible: true),
          ]),
        );
      addTearDown(bindings.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShortcutSettingsDialog(bindings: bindings)),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('shortcut-search-field')),
        'panels',
      );
      await tester.pump();
      expect(find.text('Panels'), findsOneWidget);
      for (final id in [
        EditorActionIds.toolRailOnRight,
        EditorActionIds.regionOnTop,
        EditorActionIds.resetLayout,
        'panel-timesheet',
      ]) {
        expect(
          find.byKey(ValueKey<String>('shortcut-record-$id')),
          findsOneWidget,
          reason: id,
        );
      }
    });
  });

  group('the strip', () {
    testWidgets('🚨every menu action has its row, and every row that runs '
        'something names an action — but the rows that are data', (
      tester,
    ) async {
      await pumpApp(tester);
      final rows = strip(tester).menuRows(stripContext(tester));
      final named = {for (final row in rows) ...row.shortcuts};

      // Each action of the registry, and each panel the workspace told of.
      final live = [
        for (final definition in keys(tester).definitions)
          if (definition.menuRow && definition.category != 'Timeline')
            definition.id,
      ];
      expect(live.where(isPanelActionId), isNotEmpty, reason: '⛔premise');
      expect(live.toSet().difference(named), isEmpty);
      expect(named.difference(live.toSet()), isEmpty);

      // The converse: a row with something to run and no action.
      final silent = [
        for (final row in rows)
          if (row.shortcuts.isEmpty &&
              row.onSelected != null &&
              row.submenuBuilder == null)
            row.keyValue,
      ];
      // ⚠️Not yet actions, each for its reason: a recent project is data,
      // not a command; the project settings' rows wear a VALUE as their
      // name (「FPS 24」) and wait for one of their own (I-40, later).
      expect(
        silent.where(
          (key) =>
              !key.startsWith('menu-recent-') &&
              !key.startsWith('project-settings-'),
        ),
        isEmpty,
      );
    });

    testWidgets('a row wears its action\'s name and key', (tester) async {
      await pumpApp(tester);
      keys(tester).setActivators(EditorActionIds.preferences, const [
        SingleActivator(k, control: true),
      ]);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-settings-button')),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey<String>('menu-edit-preferences'));
      expect(
        find.descendant(of: row, matching: find.text('Preferences…')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Ctrl+K')),
        findsOneWidget,
      );
    });

    testWidgets('a key opens the window its row opens', (tester) async {
      await pumpApp(tester);
      final window = find.byKey(const ValueKey<String>('preferences-dialog'));
      expect(window, findsNothing);
      await pressKeyOf(tester, EditorActionIds.preferences);
      expect(window, findsOneWidget);
    });

    testWidgets('a key flips what its checked row flips, and back', (
      tester,
    ) async {
      await pumpApp(tester);
      final menu = strip(tester).panelsMenu;
      expect(menu.canMoveToolRail, isTrue, reason: '⛔premise');
      final before = menu.toolRailOnRight;
      await pressKeyOf(tester, EditorActionIds.toolRailOnRight);
      expect(menu.toolRailOnRight, !before);
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(menu.toolRailOnRight, before);
    });

    testWidgets('a panel\'s key shows and hides the panel', (tester) async {
      await pumpApp(tester);
      final menu = strip(tester).panelsMenu;
      final panel = menu.entries.first;
      bool shown() => menu.entries
          .firstWhere((entry) => entry.tabId == panel.tabId)
          .visible;
      await pressKeyOf(tester, panelActionId(panel.tabId));
      expect(shown(), !panel.visible);
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(shown(), panel.visible);
    });

    testWidgets('a key makes what its row makes: a new project, in a tab of '
        'its own', (tester) async {
      await pumpApp(tester);
      final projects = strip(tester).projects;
      final before = projects.sessions.length;
      await pressKeyOf(tester, EditorActionIds.fileNew);
      expect(projects.sessions.length, before + 1);
    });

    testWidgets('⛔a row that is dim does nothing by key either', (
      tester,
    ) async {
      await pumpApp(tester);
      final row = strip(tester)
          .menuRows(stripContext(tester))
          .singleWhere(
            (row) =>
                row.shortcuts.contains(EditorActionIds.fileBackUpFailedCopy),
          );
      expect(row.enabled, isFalse, reason: '⛔premise: no save has failed');
      await pressKeyOf(tester, EditorActionIds.fileBackUpFailedCopy);
      expect(find.byType(AppWindow), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
