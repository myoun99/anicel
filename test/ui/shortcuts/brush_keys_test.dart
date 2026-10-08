// 🗣️I-56 (유저 2026-10-01): 「브러시 그룹이나 브러시에도 단축키 명명가능하게.
// 단축키리스트 등록」, and how the window holds them (I-56-Q1): 「브러시
// 그룹마다 접히는 묶음」 = 「브러시는 그룹마다 한 묶음으로 기본 접힘 — 그룹 줄
// 자체(그룹 키)는 묶음 제목 줄에 둔다. 검색하면 맞는 묶음이 펼쳐진다」.
//
// THE BRUSH LIBRARY IS ROWS OF THE SHORTCUT LIST: made from the library as it
// stands, kept apart from the registry's, pressed through one port, and shown
// in the window a bundle per group. What a press DOES to the hand is the
// workspace's (workspace_applies_a_preset_test).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_library_keys.dart';
import 'package:anicel/src/ui/brush/brush_press.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/shortcuts/brush_actions.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import 'package:anicel/src/ui/shortcuts/touch_shortcuts.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerFoldTwirl;

import '../../helpers/project_scratch_folder.dart';

const inks = BrushGroupId('inks');
const chalks = BrushGroupId('chalks');
const empty = BrushGroupId('empty');

BrushPreset brush(String id, String name, [BrushGroupId? group]) => BrushPreset(
  id: BrushPresetId(id),
  name: name,
  settings: BrushSettings(),
  groupId: group,
);

/// Two groups with brushes, one with none, a loose brush, and one whose
/// group is gone — written out of the order the rows come in.
final groups = [
  const BrushGroup(id: inks, name: 'Inks'),
  const BrushGroup(id: empty, name: 'Nothing yet'),
  const BrushGroup(id: chalks, name: 'Chalks'),
];
final presets = [
  brush('loose', 'Loose pencil'),
  brush('soft', 'Soft chalk', chalks),
  brush('g-pen', 'G pen', inks),
  brush('orphan', 'Orphan marker', const BrushGroupId('deleted-group')),
  brush('maru', 'Maru pen', inks),
];

const brushTool = CanvasTool.brush;
const eraser = CanvasTool.eraser;

/// A group's row and a brush's, in [tool]'s library — the brush tool's
/// unless said.
String groupId(BrushGroupId id, [CanvasTool tool = brushTool]) =>
    brushGroupActionId(tool, id);
String presetId(String id, [CanvasTool tool = brushTool]) =>
    brushPresetActionId(tool, BrushPresetId(id));

/// The library's rows for [tool], in the order they come in.
List<String> rowsFor(CanvasTool tool) => [
  groupId(inks, tool),
  presetId('g-pen', tool),
  presetId('maru', tool),
  groupId(empty, tool),
  groupId(chalks, tool),
  presetId('soft', tool),
  presetId('loose', tool),
  presetId('orphan', tool),
];

void main() {
  group('the library as rows', () {
    final rows = brushActionsOf(groups, presets);

    // 🗣️F-319 (유저 2026-10-08): 「브러시 그룹은 도구가 두곳에 있으니까 두 곳
    // 나눠서 지정하도록. 브러시도구의 브러시그룹/브러시 변경. 지우개도구의
    // 브러시그룹/브러시변경」.
    test('come once for each paint tool — the brush tool\'s, then the '
        'eraser\'s — and each time in the library\'s order: each group, the '
        'brushes that show in it, and the root section\'s after the '
        'groups', () {
      expect(rows.map((row) => row.id), [
        ...rowsFor(brushTool),
        ...rowsFor(eraser),
      ]);
      const names = [
        'Inks',
        'G pen',
        'Maru pen',
        'Nothing yet',
        'Chalks',
        'Soft chalk',
        'Loose pencil',
        'Orphan marker',
      ];
      expect(rows.map((row) => row.label), [...names, ...names]);
    });

    test('🚨a tool\'s rows are its own: no id is shared, and the brush '
        'tool\'s are the ids a key was recorded under before the eraser '
        'had rows', () {
      expect(rows.map((row) => row.id).toSet(), hasLength(rows.length));
      expect(groupId(inks), 'brush-group-inks');
      expect(presetId('maru'), 'brush-preset-maru');
      expect(groupId(inks, eraser), 'eraser-group-inks');
      expect(presetId('maru', eraser), 'eraser-preset-maru');
    });

    test('say what they press — and for which tool — ship with no key, and '
        'stand under their tool\'s category', () {
      expect(rows.first.brushPress, const BrushGroupPress(brushTool, inks));
      expect(
        rows[1].brushPress,
        const BrushPresetPress(brushTool, BrushPresetId('g-pen'), group: inks),
      );
      expect(
        rows[rowsFor(brushTool).length].brushPress,
        const BrushGroupPress(eraser, inks),
      );
      expect(
        rows.last.brushPress,
        const BrushPresetPress(eraser, BrushPresetId('orphan'), group: null),
        reason: 'a brush whose group is gone shows in the root section',
      );
      for (final row in rows) {
        expect(row.defaultActivators, isEmpty, reason: row.id);
        expect(
          row.category,
          brushActionCategories[row.brushPress!.tool],
          reason: row.id,
        );
        expect(isBrushActionId(row.id), isTrue, reason: row.id);
      }
    });

    test('every tool that holds a brush of its own has rows, under a '
        'heading of its own', () {
      final holders = CanvasTool.values.where(canvasToolPaints).toList();
      expect(brushActionCategories.keys, holders);
      expect(brushActionCategories.values.toSet(), hasLength(holders.length));
      expect(
        {for (final row in rows) row.brushPress!.tool},
        holders.toSet(),
      );
    });

    test('⛔no action of the registry reads as a brush\'s', () {
      expect(
        editorActionDefinitions.where((row) => isBrushActionId(row.id)),
        isEmpty,
      );
      expect(editorActionDefinitions.where((row) => row.brushPress != null),
          isEmpty);
    });
  });

  group('the bindings', () {
    const k = SingleActivator(LogicalKeyboardKey.keyK);

    String? actionOn(EditorShortcutBindings bindings, SingleActivator key) {
      for (final MapEntry(key: form, value: intent)
          in bindings.shortcuts.entries) {
        if (form is SingleActivator &&
            form.trigger == key.trigger &&
            form.shift == key.shift &&
            form.control == key.control) {
          return (intent as EditorActionIntent).actionId;
        }
      }
      return null;
    }

    test('hold the library\'s rows after the registry\'s, and tell their '
        'listeners only when the rows are other rows', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      var told = 0;
      bindings.addListener(() => told += 1);

      bindings.setBrushActions(brushActionsOf(groups, presets));
      expect(told, 1);
      expect(
        bindings.definitions.take(editorActionDefinitions.length),
        editorActionDefinitions,
      );
      expect(
        bindings.definitions
            .skip(editorActionDefinitions.length)
            .map((row) => row.id),
        brushActionsOf(groups, presets).map((row) => row.id),
      );
      expect(bindings.definitionFor(presetId('maru'))?.label, 'Maru pen');
      expect(
        bindings.definitionFor(EditorActionIds.undo)?.label,
        'Undo',
        reason: 'the registry\'s rows are still found',
      );

      // The same library told again — a group folded in its panel.
      bindings.setBrushActions(
        brushActionsOf(
          [for (final group in groups) group.copyWith(collapsed: true)],
          presets,
        ),
      );
      expect(told, 1);

      // A brush renamed.
      bindings.setBrushActions(
        brushActionsOf(groups, [
          for (final preset in presets)
            if (preset.id.value == 'maru')
              preset.copyWith(name: 'Round pen')
            else
              preset,
        ]),
      );
      expect(told, 2);
      expect(bindings.definitionFor(presetId('maru'))?.label, 'Round pen');

      // The library emptied: the rows go.
      bindings.setBrushActions(const []);
      expect(told, 3);
      expect(bindings.definitions, editorActionDefinitions);
      expect(bindings.definitionFor(presetId('maru')), isNull);
    });

    test('⛔a brush moved to the root section is another row though the rows '
        'read the same down the list', () {
      // One group, and its one brush after it: filed in the group or loose,
      // the ids and the names come in the same order.
      final one = [const BrushGroup(id: inks, name: 'Inks')];
      final bindings = EditorShortcutBindings()
        ..setBrushActions(brushActionsOf(one, [brush('g-pen', 'G pen', inks)]));
      addTearDown(bindings.dispose);
      var told = 0;
      bindings.addListener(() => told += 1);

      bindings.setBrushActions(brushActionsOf(one, [brush('g-pen', 'G pen')]));
      expect(told, 1);
      expect(
        bindings.definitionFor(presetId('g-pen'))?.brushPress,
        const BrushPresetPress(brushTool, BrushPresetId('g-pen'), group: null),
      );
    });

    test('a key recorded on a brush presses it, and clashes like any key', () {
      final bindings = EditorShortcutBindings()
        ..setBrushActions(brushActionsOf(groups, presets));
      addTearDown(bindings.dispose);
      expect(actionOn(bindings, k), isNull);

      bindings.setActivators(presetId('maru'), const [k]);
      expect(actionOn(bindings, k), presetId('maru'));
      expect(bindings.conflictedActionIds, isEmpty);

      // The same key on the same brush of the ERASER's library: two rows,
      // and one key cannot press both (F-319).
      bindings.setActivators(presetId('maru', eraser), const [k]);
      expect(
        bindings.conflictedActionIds,
        {presetId('maru'), presetId('maru', eraser)},
      );
      bindings.setActivators(presetId('maru', eraser), const []);
      expect(bindings.conflictedActionIds, isEmpty);

      // The eraser tool's key, recorded on a group.
      bindings.setActivators(groupId(chalks), const [
        SingleActivator(LogicalKeyboardKey.keyE),
      ]);
      expect(
        bindings.conflictedActionIds,
        {groupId(chalks), EditorActionIds.toolEraser},
      );
    });

    group('on disk', () {
      late String path;

      setUp(() async {
        final directory = await Directory.systemTemp.createTemp('brush-keys');
        deleteAfterSessionEnds(directory);
        path = '${directory.path}/overrides.json';
      });

      EditorShortcutBindings fromDisk() {
        final bindings = EditorShortcutBindings(
          store: ShortcutSettingsStore(filePath: path),
        );
        addTearDown(bindings.dispose);
        return bindings;
      }

      test('🚨a brush\'s key is read back BEFORE the library has landed, '
          'presses nothing until it has, and is written back as it '
          'was', () async {
        final first = fromDisk()
          ..setBrushActions(brushActionsOf(groups, presets));
        first.setActivators(presetId('maru'), const [k]);
        first.setTouchGesture(groupId(inks), TouchGesture.values.first);
        await first.pendingPersist;

        // The next launch: the settings come back first.
        final next = fromDisk();
        await next.restore();
        expect(next.definitionFor(presetId('maru')), isNull);
        expect(actionOn(next, k), isNull);

        // Something else is recorded before the library lands: the brush's
        // entry rides along.
        next.setActivators(EditorActionIds.undo, const [
          SingleActivator(LogicalKeyboardKey.keyU, control: true),
        ]);
        await next.pendingPersist;
        final saved =
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        expect(
          ((saved['overrides'] as Map)['anicel'] as Map).keys,
          containsAll([presetId('maru'), EditorActionIds.undo]),
        );
        expect((saved['touch'] as Map).keys, contains(groupId(inks)));

        next.setBrushActions(brushActionsOf(groups, presets));
        expect(actionOn(next, k), presetId('maru'));
        expect(next.isTouchOverridden(groupId(inks)), isTrue);
      });

      test('⛔an entry for an action that is neither the registry\'s nor a '
          'brush\'s is still dropped', () async {
        File(path).writeAsStringSync(
          '{"version":2,"preset":"anicel","overrides":{"anicel":'
          '{"no-such-action":[{"key":${LogicalKeyboardKey.keyK.keyId}}]}},'
          '"touch":{"no-such-action":"twoFingerTap"}}',
        );
        final bindings = fromDisk();
        await bindings.restore();
        expect(bindings.isOverridden('no-such-action'), isFalse);
        expect(bindings.isTouchOverridden('no-such-action'), isFalse);
      });
    });
  });

  test('each tool\'s brush category has a word in every language — and a '
      'word of its own', () {
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.en) {
        continue;
      }
      final words = [
        for (final category in brushActionCategories.values)
          AppStrings.of(language).shortcutCategory(category, ''),
      ];
      expect(words, everyElement(isNotEmpty), reason: language.name);
      expect(words.toSet(), hasLength(words.length), reason: language.name);
    }
  });

  group('the port', () {
    // ↩️A group's press went 「through the panel's tab while it is on screen
    // — the workspace's otherwise」: a third lend (`enterTab`), taken by the
    // panel mounted last. There is a panel a paint tool, so that was not
    // always the one on screen (F-319).
    test('presses a brush and a group through the workspace — each for the '
        'tool it names', () {
      final keys = BrushLibraryKeys();
      addTearDown(keys.dispose);
      final pressed = <String>[];

      // Nothing attached: a press does nothing, and does not throw.
      keys.press(const BrushGroupPress(brushTool, inks));
      keys.press(
        const BrushPresetPress(eraser, BrushPresetId('maru'), group: inks),
      );

      keys
        ..takeUp = ((tool, id) => pressed.add('take ${tool.name} ${id.value}'))
        ..openGroup = ((tool, id) =>
            pressed.add('open ${tool.name} ${id.value}'));
      keys.press(
        const BrushPresetPress(eraser, BrushPresetId('maru'), group: inks),
      );
      keys.press(const BrushGroupPress(brushTool, inks));
      keys.press(const BrushGroupPress(eraser, chalks));
      expect(pressed, [
        'take eraser maru',
        'open brush inks',
        'open eraser chalks',
      ]);
    });

    test('tells what the library holds', () {
      final keys = BrushLibraryKeys();
      addTearDown(keys.dispose);
      var told = 0;
      keys.addListener(() => told += 1);
      keys.show(groups, presets);
      expect(told, 1);
      expect(keys.groups, groups);
      expect(keys.presets, presets);
    });
  });

  group('the shortcut window', () {
    Future<EditorShortcutBindings> pump(WidgetTester tester) async {
      final bindings = EditorShortcutBindings()
        ..setBrushActions(brushActionsOf(groups, presets));
      addTearDown(bindings.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShortcutSettingsDialog(bindings: bindings)),
        ),
      );
      await tester.pump();
      return bindings;
    }

    Finder rowOf(String actionId) =>
        find.byKey(ValueKey<String>('shortcut-record-$actionId'));
    Finder twirlOf(String bundle) =>
        find.byKey(ValueKey<String>('shortcut-bundle-$bundle'));

    /// Whether [bundle]'s twirl stands open — as the twirl itself was told.
    bool isOpen(WidgetTester tester, String bundle) => tester
        .widget<LayerFoldTwirl>(
          find.byWidgetPredicate(
            (widget) =>
                widget is LayerFoldTwirl &&
                widget.keyValue == 'shortcut-bundle-$bundle',
          ),
        )
        .expanded;
    final list = find.byKey(const ValueKey<String>('shortcut-action-list'));
    final search = find.byKey(const ValueKey<String>('shortcut-search-field'));

    /// The rows of [tool]'s brushes the list holds, in order — built or not:
    /// the list is lazy and these stand at its far end, so they are read off
    /// the children it was handed. A root section's title reads
    /// `<tool>-root`.
    List<String> brushRows(WidgetTester tester, [CanvasTool tool = brushTool]) {
      final children =
          (tester.widget<ListView>(list).childrenDelegate
                  as SliverChildListDelegate)
              .children;
      return [
        for (final child in children)
          if (child.key case ValueKey<String>(:final value)
              when value.startsWith('shortcut-row-${tool.name}-'))
            value.substring('shortcut-row-'.length),
      ];
    }

    /// The category headings the list holds, in order — read the same way.
    List<String> headings(WidgetTester tester) {
      final children =
          (tester.widget<ListView>(list).childrenDelegate
                  as SliverChildListDelegate)
              .children;
      return [
        for (final child in children)
          if (child case Padding(child: Text(:final data?)))
            if (brushActionCategories.values.contains(data)) data,
      ];
    }

    /// Brings [finder]'s row into view from wherever the list stands. ⚠️A
    /// row ABOVE what is shown is not built, and dragging on down would
    /// never meet it — so a row that is not there is looked for from the
    /// top.
    Future<void> bringIn(WidgetTester tester, Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.drag(list, const Offset(0, 100000));
        await tester.pump();
      }
      await tester.dragUntilVisible(
        finder,
        list,
        const Offset(0, -300),
        maxIteration: 200,
      );
      await tester.pump();
    }

    testWidgets('holds a bundle per group, shut — once under each tool\'s '
        'heading: the titles, and no brush', (tester) async {
      await pump(tester);
      expect(headings(tester), brushActionCategories.values);
      for (final tool in [brushTool, eraser]) {
        expect(brushRows(tester, tool), [
          groupId(inks, tool),
          groupId(empty, tool),
          groupId(chalks, tool),
          '${tool.name}-root',
        ], reason: tool.name);
      }
      await bringIn(tester, twirlOf(groupId(inks)));
      expect(find.text(brushActionCategories[brushTool]!), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('shortcut-row-brush-root')),
          matching: find.text(brushRootSectionLabel),
        ),
        findsOneWidget,
      );
      for (final bundle in [groupId(inks), groupId(chalks), 'brush-root']) {
        expect(
          isOpen(tester, bundle),
          isFalse,
          reason: bundle,
        );
      }
    });

    testWidgets('a twirl opens its bundle and shuts it again — the root '
        'section\'s too, whose title is no row', (tester) async {
      await pump(tester);
      await bringIn(tester, twirlOf(groupId(inks)));
      await tester.tap(twirlOf(groupId(inks)));
      await tester.pump();
      expect(brushRows(tester), [
        groupId(inks),
        presetId('g-pen'),
        presetId('maru'),
        groupId(empty),
        groupId(chalks),
        'brush-root',
      ]);
      expect(
        isOpen(tester, groupId(inks)),
        isTrue,
      );
      expect(
        brushRows(tester, eraser),
        [
          groupId(inks, eraser),
          groupId(empty, eraser),
          groupId(chalks, eraser),
          'eraser-root',
        ],
        reason: 'the eraser\'s Inks is another bundle, and stays shut',
      );

      await bringIn(tester, twirlOf('brush-root'));
      await tester.tap(twirlOf('brush-root'));
      await tester.pump();
      expect(brushRows(tester).skip(5), [
        'brush-root',
        presetId('loose'),
        presetId('orphan'),
      ]);
      expect(rowOf('brush-root'), findsNothing);
      expect(
        brushRows(tester, eraser).last,
        'eraser-root',
        reason: 'and the eraser\'s root section is its own too',
      );

      await bringIn(tester, twirlOf(groupId(inks)));
      await tester.tap(twirlOf(groupId(inks)));
      await tester.pump();
      expect(brushRows(tester), [
        groupId(inks),
        groupId(empty),
        groupId(chalks),
        'brush-root',
        presetId('loose'),
        presetId('orphan'),
      ]);
    });

    testWidgets('the eraser\'s bundles open by their own twirls', (
      tester,
    ) async {
      await pump(tester);
      await bringIn(tester, twirlOf(groupId(inks, eraser)));
      await tester.tap(twirlOf(groupId(inks, eraser)));
      await tester.pump();
      await bringIn(tester, twirlOf('eraser-root'));
      await tester.tap(twirlOf('eraser-root'));
      await tester.pump();
      expect(brushRows(tester, eraser), [
        groupId(inks, eraser),
        presetId('g-pen', eraser),
        presetId('maru', eraser),
        groupId(empty, eraser),
        groupId(chalks, eraser),
        'eraser-root',
        presetId('loose', eraser),
        presetId('orphan', eraser),
      ]);
      expect(
        brushRows(tester),
        [groupId(inks), groupId(empty), groupId(chalks), 'brush-root'],
        reason: 'and the brush tool\'s stay shut',
      );
    });

    testWidgets('🗣️「검색하면 맞는 묶음이 펼쳐진다」 — a brush found opens its '
        'bundle on what was found, in each tool\'s rows, and the bundle '
        'stays open after', (tester) async {
      await pump(tester);
      await tester.enterText(search, 'maru');
      await tester.pump();
      expect(brushRows(tester), [groupId(inks), presetId('maru')]);
      expect(brushRows(tester, eraser), [
        groupId(inks, eraser),
        presetId('maru', eraser),
      ]);
      expect(
        isOpen(tester, groupId(inks)),
        isTrue,
      );

      // The twirl folds a bundle the search opened, like any other.
      await tester.tap(twirlOf(groupId(inks)));
      await tester.pump();
      expect(brushRows(tester), [groupId(inks)]);
      await tester.tap(twirlOf(groupId(inks)));
      await tester.pump();

      await tester.enterText(search, '');
      await tester.pump();
      expect(brushRows(tester), [
        groupId(inks),
        presetId('g-pen'),
        presetId('maru'),
        groupId(empty),
        groupId(chalks),
        'brush-root',
      ]);
    });

    testWidgets('a GROUP found shows every brush it holds; a loose brush '
        'found shows under the root section\'s word', (tester) async {
      await pump(tester);
      await tester.enterText(search, 'chalks');
      await tester.pump();
      expect(brushRows(tester), [groupId(chalks), presetId('soft')]);
      expect(find.text(brushRootSectionLabel), findsNothing);

      await tester.enterText(search, 'orphan');
      await tester.pump();
      expect(brushRows(tester), ['brush-root', presetId('orphan')]);
      expect(brushRows(tester, eraser), [
        'eraser-root',
        presetId('orphan', eraser),
      ]);
      expect(
        find.text(brushRootSectionLabel),
        findsNWidgets(2),
        reason: 'one under each tool\'s heading',
      );
      expect(headings(tester), brushActionCategories.values);
    });

    testWidgets('a tool\'s heading found shows that tool\'s rows alone', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(search, 'eraser tool brushes');
      await tester.pump();
      expect(brushRows(tester), isEmpty);
      expect(brushRows(tester, eraser), isNotEmpty);
      expect(headings(tester), [brushActionCategories[eraser]]);
    });

    testWidgets('a group\'s key is recorded on its title row — the row of '
        'the tool it is under', (tester) async {
      final bindings = await pump(tester);
      await tester.enterText(search, 'chalks');
      await tester.pump();
      await tester.tap(rowOf(groupId(chalks, eraser)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(
        bindings.activatorsFor(groupId(chalks, eraser)).single.trigger,
        LogicalKeyboardKey.keyK,
      );
      expect(bindings.activatorsFor(groupId(chalks)), isEmpty);
    });
  });
}
