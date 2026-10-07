// 🗣️I-63 (유저 2026-10-07): 「tvp기반,클튜기반,anicel 이렇게 세개 두고싶음」,
// and how a program's keys become a preset (I-63-Q3): 「초안대로 — 그
// 프로그램을 최대한 닮게」 = 「공식 키가 있는 줄은 그 프로그램의 키로, 없는
// 줄은 anicel 의 키 그대로. 키가 부딪히면 그 프로그램의 뜻을 따른다」.
//
// A PRESET IS THE KEYS THE SHORTCUT WINDOW STARTS FROM: the bindings read
// their defaults through the one in use, keep what was recorded under each
// apart, and the window picks between them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart' show CanvasTool;
import 'package:anicel/src/ui/brush/tool_press.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../guide_shots/guide_shortcut_table.dart';
import '../../helpers/project_scratch_folder.dart';

EditorActionDefinition definitionOf(String id) =>
    editorActionDefinitions.singleWhere((definition) => definition.id == id);

/// [keys] as the window writes them on a PC — 'Ctrl+Y', 'F2'.
List<String> written(Iterable<SingleActivator> keys) => [
  for (final key in keys) singleActivatorLabel(key, TargetPlatform.windows),
];

List<String> keysOf(ShortcutPreset preset, String actionId) =>
    written(presetActivators(preset, definitionOf(actionId)));

final lassoCutId = toolActionIdFor(
  const ShapeTilePress(CanvasTool.cut, CanvasShapeKind.lasso),
);
final lassoSelectId = toolActionIdFor(
  const ShapeTilePress(CanvasTool.select, CanvasShapeKind.lasso),
);

void main() {
  group('a preset\'s keys', () {
    test('anicel is the registry, row for row', () {
      for (final definition in editorActionDefinitions) {
        expect(
          written(presetActivators(ShortcutPreset.anicel, definition)),
          written(definition.defaultActivators),
          reason: definition.id,
        );
      }
    });

    test('⛔fixture premise: the registry\'s keys the rows below move', () {
      const anicel = ShortcutPreset.anicel;
      expect(keysOf(anicel, EditorActionIds.toolFill), ['F']);
      expect(keysOf(anicel, EditorActionIds.toolGuide), ['G']);
      expect(keysOf(anicel, EditorActionIds.layerUp), ['↑', 'W']);
      expect(keysOf(anicel, EditorActionIds.onionSkinToggle), ['T']);
      expect(keysOf(anicel, lassoCutId), ['C']);
      expect(keysOf(anicel, EditorActionIds.editDelete), ['Delete']);
      expect(keysOf(anicel, EditorActionIds.editClearPixels), ['Backspace']);
    });

    test('an action the program names takes the program\'s keys and no '
        'other', () {
      const clipStudio = ShortcutPreset.clipStudio;
      expect(keysOf(clipStudio, EditorActionIds.toolFill), ['G']);
      expect(keysOf(clipStudio, EditorActionIds.toolGuide), ['U']);
      expect(keysOf(clipStudio, EditorActionIds.toolSelect), ['M']);
      expect(keysOf(clipStudio, EditorActionIds.toolText), ['T']);
      expect(keysOf(clipStudio, EditorActionIds.toolBrush), ['B', 'P']);
      // The arrows and W · S leave the rows with them: the program's key
      // for 「위 레이어」 is the row's only one.
      expect(keysOf(clipStudio, EditorActionIds.layerUp), ['Alt+]']);
      expect(keysOf(clipStudio, EditorActionIds.layerDown), ['Alt+[']);
      expect(keysOf(clipStudio, EditorActionIds.redo), [
        'Ctrl+Y',
        'Ctrl+Shift+Z',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.editCut), ['Ctrl+X', 'F2']);
      expect(keysOf(clipStudio, EditorActionIds.editCopy), ['Ctrl+C', 'F3']);
      expect(keysOf(clipStudio, EditorActionIds.editPasteIndependent), [
        'Ctrl+V',
        'F4',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.canvasRotateCcw), ['-']);
      expect(keysOf(clipStudio, EditorActionIds.canvasRotateCw), ['^']);
      expect(keysOf(clipStudio, EditorActionIds.canvasZoomIn), [
        'Ctrl+Numpad Add',
        'Ctrl+;',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.canvasZoomOut), [
        'Ctrl+Numpad Subtract',
        'Ctrl+-',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.fileSaveAs), [
        'Alt+Shift+S',
        'Ctrl+Shift+S',
        'Ctrl+Alt+S',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.toolTransformFree), [
        'Ctrl+Shift+T',
      ]);
      expect(keysOf(clipStudio, blendModeActionId(BrushBlendMode.erase)), [
        'C',
      ]);
    });

    test('an action the program does not name keeps the registry\'s keys — '
        'its animation commands have none', () {
      const clipStudio = ShortcutPreset.clipStudio;
      expect(keysOf(clipStudio, EditorActionIds.drawingPrevious), ['←', 'A']);
      expect(keysOf(clipStudio, EditorActionIds.frameNext), [
        'Shift+→',
        'Shift+D',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.playbackToggle), ['Shift+X']);
      expect(keysOf(clipStudio, EditorActionIds.timelineComma3), ['3']);
      expect(keysOf(clipStudio, EditorActionIds.toolCutStamp), ['V']);
      expect(keysOf(clipStudio, EditorActionIds.editInstance), ['Shift+F']);
      // A tile of a tool whose key went to the rail tool alone keeps its own.
      expect(keysOf(clipStudio, lassoSelectId), ['X']);
    });

    test('a key the program gave to something else leaves the action that '
        'had it — 「부딪히면 그 프로그램의 뜻을 따른다」', () {
      const clipStudio = ShortcutPreset.clipStudio;
      // T is the text tool's, C the erase blend's, F2 · F4 cut and paste.
      expect(keysOf(clipStudio, EditorActionIds.onionSkinToggle), isEmpty);
      expect(keysOf(clipStudio, lassoCutId), isEmpty);
      expect(
        keysOf(clipStudio, blendModeActionId(BrushBlendMode.behind)),
        isEmpty,
      );
      expect(
        keysOf(clipStudio, blendModeActionId(BrushBlendMode.darken)),
        isEmpty,
      );
      expect(keysOf(clipStudio, blendModeActionId(BrushBlendMode.color)), [
        'F1',
      ]);
    });

    test('⛔only the key that was taken leaves: an action with another key '
        'keeps that one', () {
      // No row of the registry has one key taken and one left under this
      // preset today, so the rule is asked of a row made for it.
      const twoKeys = EditorActionDefinition(
        id: 'a-row-no-preset-names',
        label: '',
        category: '',
        defaultActivators: [
          SingleActivator(LogicalKeyboardKey.keyG),
          SingleActivator(LogicalKeyboardKey.keyK),
          SingleActivator(LogicalKeyboardKey.keyG, shift: true),
        ],
      );
      expect(
        written(presetActivators(ShortcutPreset.clipStudio, twoKeys)),
        ['K', 'Shift+G'],
        reason: 'G is the fill tool\'s there; Shift+G is another key',
      );
      expect(
        written(presetActivators(ShortcutPreset.anicel, twoKeys)),
        ['G', 'K', 'Shift+G'],
      );
    });

    test('where one program key stood on several rows of the table it is on '
        'one: the same command before a similar one, the rail tool before '
        'its tiles', () {
      const clipStudio = ShortcutPreset.clipStudio;
      // Delete — the program's Erase is 픽셀 비우기; the pill's 삭제 only
      // resembles it.
      expect(keysOf(clipStudio, EditorActionIds.editClearPixels), [
        'Delete',
        'Backspace',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.editDelete), isEmpty);
      // Ctrl+T — Scale/Rotate is the normal transform.
      expect(keysOf(clipStudio, EditorActionIds.toolTransformNormal), [
        'Ctrl+T',
      ]);
      expect(keysOf(clipStudio, EditorActionIds.toolTransform), isEmpty);
      // G · M · U — 「도구 버튼 하나에만 준다」.
      expect(keysOf(clipStudio, EditorActionIds.toolFillBucket), isEmpty);
      for (final shape in CanvasShapeKind.values) {
        for (final verb in [CanvasTool.fillShape, CanvasTool.select]) {
          final tile = toolActionIdFor(ShapeTilePress(verb, shape));
          expect(
            keysOf(clipStudio, tile),
            keysOf(ShortcutPreset.anicel, tile),
            reason: '$tile keeps what the registry gives it',
          );
        }
      }
    });

    for (final preset in ShortcutPreset.values) {
      test('${preset.name} ships with no two actions on one key', () {
        final bindings = EditorShortcutBindings()..setPreset(preset);
        addTearDown(bindings.dispose);
        expect(bindings.conflictedActionIds, isEmpty);
      });

      test('${preset.name} names only actions the registry has', () {
        final registry = {
          for (final definition in editorActionDefinitions) definition.id,
        };
        expect(
          presetNamedActionIds(preset).where((id) => !registry.contains(id)),
          isEmpty,
        );
      });
    }

    test('⛔fixture premise: the program\'s preset does name actions', () {
      expect(presetNamedActionIds(ShortcutPreset.clipStudio), isNotEmpty);
      expect(presetNamedActionIds(ShortcutPreset.anicel), isEmpty);
    });

    test('a settings file\'s word finds its preset, and a word no build '
        'knows finds none', () {
      for (final preset in ShortcutPreset.values) {
        expect(ShortcutPreset.named(preset.name), preset);
      }
      expect(ShortcutPreset.named('no-such-preset'), isNull);
      expect(ShortcutPreset.named(null), isNull);
      expect(ShortcutPreset.named(3), isNull);
    });
  });

  group('the bindings', () {
    /// The action a bare or modified key dispatches, or null.
    String? actionOn(EditorShortcutBindings bindings, SingleActivator key) {
      for (final MapEntry(key: form, value: intent)
          in bindings.shortcuts.entries) {
        if (form is SingleActivator && activatorsEqual(form, key)) {
          return (intent as EditorActionIntent).actionId;
        }
      }
      return null;
    }

    const g = SingleActivator(LogicalKeyboardKey.keyG);
    const f = SingleActivator(LogicalKeyboardKey.keyF);

    test('open on anicel, and read their keys through the preset in use', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      expect(bindings.preset, ShortcutPreset.anicel);
      expect(actionOn(bindings, f), EditorActionIds.toolFill);
      expect(actionOn(bindings, g), EditorActionIds.toolGuide);

      var told = 0;
      bindings.addListener(() => told += 1);
      bindings.setPreset(ShortcutPreset.clipStudio);

      expect(bindings.preset, ShortcutPreset.clipStudio);
      expect(told, 1);
      expect(actionOn(bindings, g), EditorActionIds.toolFill);
      expect(actionOn(bindings, f), isNull, reason: 'F presses nothing there');
      expect(
        written(bindings.activatorsFor(EditorActionIds.toolFill)),
        ['G'],
      );
      expect(
        written(bindings.defaultActivatorsFor(EditorActionIds.toolFill)),
        ['G'],
      );

      bindings.setPreset(ShortcutPreset.clipStudio);
      expect(told, 1, reason: 'the preset already in use changes nothing');
    });

    test('the held pan stays a hold under a preset that names its key', () {
      final bindings = EditorShortcutBindings()
        ..setPreset(ShortcutPreset.clipStudio);
      addTearDown(bindings.dispose);
      expect(
        written(bindings.activatorsFor(EditorActionIds.canvasPanHold)),
        ['Space'],
      );
      expect(
        actionOn(bindings, const SingleActivator(LogicalKeyboardKey.space)),
        isNull,
        reason: 'a hold is never an intent in the map',
      );
    });

    test('a preset\'s command key is ⌘ on a Mac, as the registry\'s is', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final bindings = EditorShortcutBindings()
        ..setPreset(ShortcutPreset.clipStudio);
      addTearDown(bindings.dispose);
      final zoomIn = bindings.activatorsFor(EditorActionIds.canvasZoomIn);
      expect(zoomIn, hasLength(2));
      for (final key in zoomIn) {
        expect(key.meta, isTrue);
        expect(key.control, isFalse);
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('what is recorded under a preset stays with that preset', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      const recordedOnAnicel = SingleActivator(
        LogicalKeyboardKey.keyU,
        control: true,
        alt: true,
      );
      bindings.setActivators(EditorActionIds.undo, const [recordedOnAnicel]);
      expect(bindings.isOverridden(EditorActionIds.undo), isTrue);

      bindings.setPreset(ShortcutPreset.clipStudio);
      expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
      expect(written(bindings.activatorsFor(EditorActionIds.undo)), ['Ctrl+Z']);

      bindings.setActivators(EditorActionIds.toolFill, const [
        SingleActivator(LogicalKeyboardKey.keyK),
      ]);
      expect(written(bindings.activatorsFor(EditorActionIds.toolFill)), ['K']);

      bindings.setPreset(ShortcutPreset.anicel);
      expect(
        written(bindings.activatorsFor(EditorActionIds.undo)),
        ['Ctrl+Alt+U'],
        reason: 'the recording waited on its own preset',
      );
      expect(
        written(bindings.activatorsFor(EditorActionIds.toolFill)),
        ['F'],
        reason: 'the other preset\'s recording did not come along',
      );
      expect(bindings.isOverridden(EditorActionIds.toolFill), isFalse);
    });

    test('a key equal to the PRESET\'s own clears the recording — the '
        'registry\'s key is a recording there', () {
      final bindings = EditorShortcutBindings()
        ..setPreset(ShortcutPreset.clipStudio);
      addTearDown(bindings.dispose);

      bindings.setActivators(EditorActionIds.toolFill, const [f]);
      expect(bindings.isOverridden(EditorActionIds.toolFill), isTrue);
      expect(written(bindings.activatorsFor(EditorActionIds.toolFill)), ['F']);

      bindings.setActivators(EditorActionIds.toolFill, const [g]);
      expect(bindings.isOverridden(EditorActionIds.toolFill), isFalse);
    });

    test('reset all puts back the preset in use and leaves the other\'s '
        'recordings', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      bindings.setActivators(EditorActionIds.undo, const [
        SingleActivator(LogicalKeyboardKey.keyU, control: true),
      ]);
      bindings.setPreset(ShortcutPreset.clipStudio);
      bindings.setActivators(EditorActionIds.toolFill, const [f]);

      bindings.resetAll();
      expect(written(bindings.activatorsFor(EditorActionIds.toolFill)), ['G']);

      bindings.setPreset(ShortcutPreset.anicel);
      expect(written(bindings.activatorsFor(EditorActionIds.undo)), ['Ctrl+U']);
    });

    group('on disk', () {
      late String path;

      setUp(() async {
        final directory = await Directory.systemTemp.createTemp('presets-test');
        deleteAfterSessionEnds(directory);
        path = '${directory.path}/overrides.json';
      });

      Future<EditorShortcutBindings> restored() async {
        final bindings = EditorShortcutBindings(
          store: ShortcutSettingsStore(filePath: path),
        );
        addTearDown(bindings.dispose);
        await bindings.restore();
        return bindings;
      }

      test('the preset in use and each preset\'s recordings come '
          'back', () async {
        final bindings = EditorShortcutBindings(
          store: ShortcutSettingsStore(filePath: path),
        );
        addTearDown(bindings.dispose);
        bindings.setActivators(EditorActionIds.undo, const [
          SingleActivator(LogicalKeyboardKey.keyU, control: true),
        ]);
        bindings.setPreset(ShortcutPreset.clipStudio);
        bindings.setActivators(EditorActionIds.toolFill, const [f]);
        await bindings.pendingPersist;

        final saved =
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        expect(saved['version'], 2);
        expect(saved['preset'], 'clipStudio');
        expect((saved['overrides'] as Map).keys, ['anicel', 'clipStudio']);
        expect((saved['overrides'] as Map)['anicel'], {
          EditorActionIds.undo: [
            {'key': LogicalKeyboardKey.keyU.keyId, 'ctrl': true},
          ],
        });

        final again = await restored();
        expect(again.preset, ShortcutPreset.clipStudio);
        expect(written(again.activatorsFor(EditorActionIds.toolFill)), ['F']);
        expect(written(again.activatorsFor(EditorActionIds.undo)), ['Ctrl+Z']);
        again.setPreset(ShortcutPreset.anicel);
        expect(written(again.activatorsFor(EditorActionIds.undo)), ['Ctrl+U']);
        expect(written(again.activatorsFor(EditorActionIds.toolFill)), ['F']);
        expect(again.isOverridden(EditorActionIds.toolFill), isFalse);
      });

      test('switching the preset alone is saved', () async {
        final bindings = EditorShortcutBindings(
          store: ShortcutSettingsStore(filePath: path),
        );
        addTearDown(bindings.dispose);
        bindings.setPreset(ShortcutPreset.clipStudio);
        await bindings.pendingPersist;
        expect((await restored()).preset, ShortcutPreset.clipStudio);
      });

      test('↩️a file from before the presets: its recordings are anicel\'s, '
          'and anicel is in use', () async {
        File(path).writeAsStringSync(
          '{"version":1,"overrides":{"edit-undo":'
          '[{"key":${LogicalKeyboardKey.keyW.keyId},"ctrl":true}]},'
          '"touch":{"edit-redo":"twoFingerTap"}}',
        );
        final bindings = await restored();
        expect(bindings.preset, ShortcutPreset.anicel);
        expect(
          written(bindings.activatorsFor(EditorActionIds.undo)),
          ['Ctrl+W'],
        );
        expect(bindings.isTouchOverridden(EditorActionIds.redo), isTrue);
        bindings.setPreset(ShortcutPreset.clipStudio);
        expect(
          written(bindings.activatorsFor(EditorActionIds.undo)),
          ['Ctrl+Z'],
          reason: 'recorded over the registry\'s keys, not over this preset',
        );
      });

      test('a preset no build knows reads as anicel, and a preset\'s '
          'recordings that are not a table read as none', () async {
        File(path).writeAsStringSync(
          '{"version":2,"preset":"no-such-preset","overrides":'
          '{"anicel":7,"clipStudio":{"tool-fill":'
          '[{"key":${LogicalKeyboardKey.keyK.keyId}}],"no-such-action":[],'
          '"edit-undo":5}}}',
        );
        final bindings = await restored();
        expect(bindings.preset, ShortcutPreset.anicel);
        expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
        bindings.setPreset(ShortcutPreset.clipStudio);
        expect(
          written(bindings.activatorsFor(EditorActionIds.toolFill)),
          ['K'],
        );
        // An action no build knows, and one whose keys are not a list.
        expect(bindings.isOverridden('no-such-action'), isFalse);
        expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
      });

      test('a restore replaces what was recorded before it — on every '
          'preset', () async {
        File(path).writeAsStringSync(
          '{"version":2,"preset":"anicel","overrides":{}}',
        );
        final bindings = EditorShortcutBindings(
          store: ShortcutSettingsStore(filePath: path),
        );
        addTearDown(bindings.dispose);
        // Recorded in memory only: `File(path)` is rewritten below before
        // the restore reads it.
        bindings.setActivators(EditorActionIds.undo, const [f]);
        bindings.setPreset(ShortcutPreset.clipStudio);
        bindings.setActivators(EditorActionIds.toolFill, const [f]);
        await bindings.pendingPersist;
        File(path).writeAsStringSync(
          '{"version":2,"preset":"anicel","overrides":{}}',
        );

        await bindings.restore();
        expect(bindings.preset, ShortcutPreset.anicel);
        expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
        bindings.setPreset(ShortcutPreset.clipStudio);
        expect(bindings.isOverridden(EditorActionIds.toolFill), isFalse);
      });
    });
  });

  group('the shortcut window', () {
    Future<EditorShortcutBindings> pump(WidgetTester tester) async {
      final bindings = EditorShortcutBindings();
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

    Finder pillOf(ShortcutPreset preset) =>
        find.byKey(ValueKey<String>('shortcut-preset-${preset.name}'));

    bool chosen(WidgetTester tester, ShortcutPreset preset) =>
        tester.widget<Pill>(pillOf(preset)).selected;

    /// The key chips on [actionId]'s row, as written.
    List<String> chipsOf(WidgetTester tester, String actionId) {
      final row = find.ancestor(
        of: find.byKey(ValueKey<String>('shortcut-record-$actionId')),
        matching: find.byType(Row),
      );
      return [
        for (final chip in tester.widgetList<Chip>(
          find.descendant(of: row.first, matching: find.byType(Chip)),
        ))
          if (chip.avatar == null) (chip.label as Text).data!,
      ];
    }

    testWidgets('offers every preset as one pill strip, the one in use '
        'chosen', (tester) async {
      await pump(tester);
      expect(find.byType(PillStrip), findsOneWidget);
      for (final preset in ShortcutPreset.values) {
        expect(pillOf(preset), findsOneWidget, reason: preset.name);
        expect(
          chosen(tester, preset),
          preset == ShortcutPreset.anicel,
          reason: preset.name,
        );
      }
      expect(
        tester.widget<Pill>(pillOf(ShortcutPreset.clipStudio)).label,
        ShortcutPreset.clipStudio.label,
      );
    });

    testWidgets('a pill reads in the program language — the app\'s own name '
        'in every one', (tester) async {
      final before = AppText.settings.value;
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
        notationLanguage: AppLanguage.ko,
      );
      addTearDown(() => AppText.settings.value = before);
      await pump(tester);
      expect(
        tester.widget<Pill>(pillOf(ShortcutPreset.clipStudio)).label,
        '클립 스튜디오 기반',
      );
      expect(
        tester.widget<Pill>(pillOf(ShortcutPreset.anicel)).label,
        'Anicel',
      );
    });

    testWidgets('a pill puts its preset in use, and the rows show its keys', (
      tester,
    ) async {
      final bindings = await pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('shortcut-search-field')),
        definitionOf(EditorActionIds.toolFill).label,
      );
      await tester.pump();
      expect(chipsOf(tester, EditorActionIds.toolFill), ['F']);

      await tester.tap(pillOf(ShortcutPreset.clipStudio));
      await tester.pump();

      expect(bindings.preset, ShortcutPreset.clipStudio);
      expect(chosen(tester, ShortcutPreset.clipStudio), isTrue);
      expect(chosen(tester, ShortcutPreset.anicel), isFalse);
      expect(chipsOf(tester, EditorActionIds.toolFill), ['G']);

      await tester.tap(pillOf(ShortcutPreset.anicel));
      await tester.pump();
      expect(bindings.preset, ShortcutPreset.anicel);
      expect(chipsOf(tester, EditorActionIds.toolFill), ['F']);
    });
  });

  group('the words', () {
    test('every preset but the app\'s own has a name in every language', () {
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.en) {
          continue;
        }
        final strings = AppStrings.of(language);
        for (final preset in ShortcutPreset.values) {
          final name = strings.shortcutPresetName(preset.name, '');
          expect(
            name.isNotEmpty,
            preset != ShortcutPreset.anicel,
            reason: '${language.name} · ${preset.name}',
          );
        }
      }
    });
  });

  group('the guide\'s shortcut page', () {
    /// The page's sections by their `## ` heading.
    Map<String, String> sectionsOf(String markdown) => {
      for (final section in markdown.split('\n## ').skip(1))
        section.substring(0, section.indexOf('\n')): section,
    };

    /// The row of [section] that names [action].
    String rowOf(String section, String action) => section
        .split('\n')
        .singleWhere((line) => line.startsWith('| $action |'));

    test('writes every preset\'s keys under its name', () {
      final sections = sectionsOf(shortcutTableMarkdown(AppLanguage.ko));
      expect(sections.keys, ['Anicel', '클립 스튜디오 기반']);
      final anicel = sections['Anicel']!;
      final clipStudio = sections['클립 스튜디오 기반']!;

      const fill = '채우기 도구';
      expect(rowOf(anicel, fill), '| $fill | <kbd>F</kbd> |');
      expect(rowOf(clipStudio, fill), '| $fill | <kbd>G</kbd> |');
      // A row with no key under a preset is not written there.
      const onion = '어니언 스킨 켜기/끄기';
      expect(rowOf(anicel, onion), contains('<kbd>T</kbd>'));
      expect(clipStudio, isNot(contains('| $onion |')));
      // A key that is another one on a Mac is written both ways.
      expect(
        rowOf(clipStudio, '다른 이름으로 저장…'),
        contains('<kbd class="k-mac">⌥⇧S</kbd>'),
      );
    });

    test('⛔fixture premise: the page names its groups under each preset', () {
      final page = shortcutTableMarkdown(AppLanguage.en);
      expect(sectionsOf(page).keys, ['Anicel', 'Clip Studio based']);
      expect('\n### Tools\n'.allMatches(page), hasLength(2));
    });
  });
}
