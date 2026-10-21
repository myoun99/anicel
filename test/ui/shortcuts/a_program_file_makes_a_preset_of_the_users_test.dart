import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/services/shortcuts/program_keymap.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart' show CanvasTool;
import 'package:anicel/src/ui/brush/picked_file.dart';
import 'package:anicel/src/ui/shortcuts/brush_actions.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_file_import.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/program_shortcut_files.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️I-107 (유저): 「tvp나 클튜의 단축키파일 임포트 가능하게. 대응하는것만
/// 대응하게 해도 되니까」, and where the keys go (I-107-Q1, 유저
/// 2026-10-18): 「가져올땐 새 프리셋으로서 등록」 — a preset of the user's,
/// over the program's own, which comes into use.
///
/// ★THE PRESETS' LAW, WITH THE FILES AS THE PROGRAM (I-63-Q3): an action
/// they give keys takes those and no other; every other action keeps what
/// it holds, less any key they gave another.
void main() {
  late Directory folder;
  late EditorShortcutBindings bindings;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_program_keys_');
    bindings = EditorShortcutBindings();
  });
  tearDown(() {
    bindings.dispose();
    deleteTempQuietly(folder);
  });

  /// [actionId]'s live keys as the window writes them on a PC.
  List<String> keysOf(String actionId, [EditorShortcutBindings? held]) => [
    for (final key in (held ?? bindings).activatorsFor(actionId))
      singleActivatorLabel(key, TargetPlatform.windows),
  ];

  /// TVPaint's config.ini, its [keyboard] section holding [keyboard].
  PickedFile configIni(List<String> keyboard) => (
    name: 'config.ini',
    bytes: utf8.encode(['[keyboard]', ...keyboard].join('\n')),
  );

  String shownName(ShortcutPreset preset) =>
      AppText.strings.shortcutPresetName(preset.name, preset.label);

  UserShortcutPreset inUse([EditorShortcutBindings? held]) =>
      (held ?? bindings).preset as UserShortcutPreset;

  PickedFile menus() => (
    name: 'default.khc',
    bytes: clipShortcutSetBytes(folder, [
      ('viewreversehorz', 'H', 2),
      ('redo', 'Y', 2),
    ]),
  );
  PickedFile tools() => (
    name: 'EditImageTool.todb',
    bytes: clipToolPaletteBytes(folder, [('펜', 22, 20), ('붓', 14, 22)]),
  );

  test('⛔fixture premise: what the TVPaint preset holds where the files '
      'below speak', () {
    bindings.setPreset(ShortcutPreset.tvpaint);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
    expect(keysOf(EditorActionIds.canvasZoomIn), ['>']);
    expect(keysOf(EditorActionIds.canvasFlipHorizontal), ['[']);
    expect(keysOf(EditorActionIds.canvasFit), ['Shift+V', 'Shift+F11']);
  });

  test('a TVPaint keymap makes a new preset of the user\'s over the TVPaint '
      'preset, named for both, which comes into use — and an action it '
      'gives keys takes those and no other', () {
    expect(bindings.preset, ShortcutPreset.clipStudio);

    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);

    expect(bindings.userPresets, [inUse()]);
    expect(inUse().base, ShortcutPreset.tvpaint);
    expect(inUse().name, '${shownName(ShortcutPreset.tvpaint)} — config.ini');
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z']);
  });

  test('a key the file puts on one action leaves every other that held it '
      '— the user\'s own included', () {
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(EditorActionIds.cutNew, const [
        SingleActivator(LogicalKeyboardKey.f9),
      ]);

    importShortcutFiles(bindings, [
      configIni(['braquet=ZoomIn', 'f9=Undo']),
    ]);

    expect(keysOf(EditorActionIds.canvasZoomIn), ['[']);
    expect(keysOf(EditorActionIds.undo), ['F9']);
    expect(keysOf(EditorActionIds.canvasFlipHorizontal), isEmpty);
    expect(keysOf(EditorActionIds.cutNew), isEmpty);
  });

  test('an action the file gives no key keeps what it holds in the layout '
      'in use — the preset\'s, or the user\'s', () {
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(EditorActionIds.canvasStraighten, const [
        SingleActivator(LogicalKeyboardKey.f9),
      ]);

    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);

    expect(keysOf(EditorActionIds.canvasFit), ['Shift+V', 'Shift+F11']);
    expect(keysOf(EditorActionIds.canvasStraighten), ['F9']);
  });

  test('with another program\'s layout in use, it is the file\'s program\'s '
      'preset, as the user has it, that an action keeps its keys of', () {
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(EditorActionIds.canvasStraighten, const [
        SingleActivator(LogicalKeyboardKey.f9),
      ])
      ..setPreset(ShortcutPreset.clipStudio)
      ..setActivators(EditorActionIds.canvasFit, const [
        SingleActivator(LogicalKeyboardKey.f8),
      ]);

    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);

    expect(keysOf(EditorActionIds.canvasStraighten), ['F9']);
    expect(keysOf(EditorActionIds.canvasFit), ['Shift+V', 'Shift+F11']);
  });

  test('CLIP STUDIO\'s two files — its menus\' keys and its tools\' — '
      'opened together make ONE preset, named for both', () {
    final said = importShortcutFiles(bindings, [menus(), tools()]);

    expect(said, [AppText.strings.shortcutFileImported(inUse().name, 4, 0)]);
    expect(bindings.userPresets, [inUse()]);
    expect(
      inUse().name,
      '${shownName(ShortcutPreset.clipStudio)} — '
      'default.khc · EditImageTool.todb',
    );
    expect(keysOf(EditorActionIds.canvasFlipHorizontal), ['Shift+H']);
    expect(keysOf(EditorActionIds.redo), ['Shift+Y']);
    expect(keysOf(EditorActionIds.toolBrush), ['N', 'V']);
  });

  test('opened one after the other, in either order, the second builds on '
      'the first and takes nothing back of it', () {
    for (final order in [
      [menus(), tools()],
      [tools(), menus()],
    ]) {
      final held = EditorShortcutBindings();
      addTearDown(held.dispose);
      for (final file in order) {
        importShortcutFiles(held, [file]);
      }
      expect(held.userPresets, hasLength(2));
      expect(keysOf(EditorActionIds.canvasFlipHorizontal, held), [
        'Shift+H',
      ]);
      expect(keysOf(EditorActionIds.redo, held), ['Shift+Y']);
      expect(keysOf(EditorActionIds.toolBrush, held), ['N', 'V']);
    }
  });

  test('a key recorded for a brush the list does not show yet rides into '
      'the new preset — recorded over the layout in use, or one it was '
      'made with', () {
    final maru = brushPresetActionId(
      CanvasTool.brush,
      const BrushPresetId('maru'),
    );
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(maru, const [SingleActivator(LogicalKeyboardKey.f9)]);
    expect(bindings.definitionFor(maru), isNull, reason: '⛔fixture premise');

    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);
    expect(keysOf(maru), ['F9']);

    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);
    expect(keysOf(maru), ['F9']);
  });

  test('two programs\' files opened together make a preset each', () {
    importShortcutFiles(bindings, [
      menus(),
      configIni(['ctrl z=Undo']),
    ]);

    expect([for (final preset in bindings.userPresets) preset.base], [
      ShortcutPreset.clipStudio,
      ShortcutPreset.tvpaint,
    ]);
    expect(inUse().base, ShortcutPreset.tvpaint);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z']);
    bindings.setPreset(bindings.userPresets.first);
    expect(keysOf(EditorActionIds.redo), ['Shift+Y']);
  });

  test('what the file brought is the keys the preset was made with: the '
      'window\'s reset takes back only what was recorded over them', () {
    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);
    expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
    bindings.setActivators(EditorActionIds.undo, const [
      SingleActivator(LogicalKeyboardKey.f2),
    ]);
    expect(bindings.isOverridden(EditorActionIds.undo), isTrue);

    bindings.resetAll();

    expect(bindings.preset, bindings.userPresets.single);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z']);
  });

  test('the TVPaint preset itself is left as it was', () {
    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);

    bindings.setPreset(ShortcutPreset.tvpaint);

    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
    expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
  });

  test('a Mac presses the file\'s Ctrl as ⌘, as it does a preset\'s', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo']),
    ]);

    final undo = bindings.activatorsFor(EditorActionIds.undo).single;
    expect((undo.meta, undo.control), (true, false));
  });

  test('what is said: the new preset, how many keys came and how many had '
      'nothing to go on', () {
    final said = importShortcutFiles(bindings, [
      configIni(['ctrl z=Undo', 'a=ZoomShake', 'ctrl wheel up=ZoomIn']),
    ]);

    expect(said, [AppText.strings.shortcutFileImported(inUse().name, 1, 2)]);
  });

  test('a file no keys can be read out of is said so, and makes no '
      'preset', () {
    final said = importShortcutFiles(bindings, [
      (name: 'notes.txt', bytes: utf8.encode('메모')),
    ]);

    expect(said, [AppText.strings.shortcutFileUnreadable('notes.txt')]);
    expect(bindings.userPresets, isEmpty);
    expect(bindings.preset, ShortcutPreset.clipStudio);
  });

  // ↩️It kept the registry's H until F-417, where a row its program does not
  // name took the other program's keys.
  test('a row with no keys names none: its action takes what it holds '
      'without the program — TVPaint\'s, under the Clip Studio preset', () {
    final rows = presetRows(ShortcutPreset.clipStudio);
    expect(
      rows[EditorActionIds.canvasFlipHorizontal]!.keys,
      isEmpty,
      reason: '⛔fixture premise',
    );

    bindings.setPreset(ShortcutPreset.clipStudio);

    expect(keysOf(EditorActionIds.canvasFlipHorizontal), ['[']);
  });

  test('every TVPaint command a row names has its Japanese name, for the '
      'text the program saves — and there is no name of another', () {
    expect(tvpaintShownNames.keys.toSet(), {
      for (final row in presetRows(ShortcutPreset.tvpaint).values)
        ...row.commands,
    });
  });
}
