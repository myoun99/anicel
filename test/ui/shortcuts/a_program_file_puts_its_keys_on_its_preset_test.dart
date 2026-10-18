import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/shortcuts/program_keymap.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/program_shortcut_files.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️I-107 (유저): 「tvp나 클튜의 단축키파일 임포트 가능하게. 대응하는것만
/// 대응하게 해도 되니까」, and where the keys go (I-107-Q1, 추천 a): 「그
/// 프로그램 기반 프리셋으로」 — the program's preset comes into use, and what
/// the file says is that preset's change.
///
/// ★THE PRESETS' LAW, WITH THE FILE AS THE PROGRAM (I-63-Q3): an action the
/// file gives keys takes those and no other; every other action keeps what
/// it holds, less any key the file gave another.
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

  ProgramKeymap tvpaint(List<String> keyboard) =>
      readTvpaintKeymap(['[keyboard]', ...keyboard].join('\n'))!;

  test('⛔fixture premise: what the TVPaint preset holds where the files '
      'below speak', () {
    bindings.setPreset(ShortcutPreset.tvpaint);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
    expect(keysOf(EditorActionIds.canvasZoomIn), ['>']);
    expect(keysOf(EditorActionIds.canvasFlipHorizontal), ['[']);
    expect(keysOf(EditorActionIds.canvasFit), ['Shift+V', 'Shift+F11']);
  });

  test('a TVPaint keymap goes on the TVPaint preset, which comes into use — '
      'and an action it gives keys takes those and no other', () {
    expect(bindings.preset, ShortcutPreset.clipStudio);

    bindings.importProgramKeys(tvpaint(['ctrl z=Undo']));

    expect(bindings.preset, ShortcutPreset.tvpaint);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z']);
  });

  test('a key the file puts on one action leaves every other that held it '
      '— the user\'s own included', () {
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(EditorActionIds.cutNew, const [
        SingleActivator(LogicalKeyboardKey.f9),
      ]);

    bindings.importProgramKeys(tvpaint(['braquet=ZoomIn', 'f9=Undo']));

    expect(keysOf(EditorActionIds.canvasZoomIn), ['[']);
    expect(keysOf(EditorActionIds.undo), ['F9']);
    expect(keysOf(EditorActionIds.canvasFlipHorizontal), isEmpty);
    expect(keysOf(EditorActionIds.cutNew), isEmpty);
  });

  test('an action the file gives no key keeps what it holds — the '
      'preset\'s, or the user\'s', () {
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(EditorActionIds.canvasStraighten, const [
        SingleActivator(LogicalKeyboardKey.f9),
      ]);

    bindings.importProgramKeys(tvpaint(['ctrl z=Undo']));

    expect(keysOf(EditorActionIds.canvasFit), ['Shift+V', 'Shift+F11']);
    expect(keysOf(EditorActionIds.canvasStraighten), ['F9']);
  });

  test('CLIP STUDIO\'s two files — its menus\' keys and its tools\' — may '
      'come in either first, and neither takes back what the other '
      'brought', () {
    final menus = readShortcutFile(
      'default.khc',
      clipShortcutSetBytes(folder, [
        ('viewreversehorz', 'H', 2),
        ('redo', 'Y', 2),
      ]),
    )!;
    final tools = readShortcutFile(
      'EditImageTool.todb',
      clipToolPaletteBytes(folder, [('펜', 22, 20), ('붓', 14, 22)]),
    )!;

    for (final order in [
      [menus, tools],
      [tools, menus],
    ]) {
      final held = EditorShortcutBindings();
      addTearDown(held.dispose);
      for (final file in order) {
        held.importProgramKeys(file);
      }
      expect(held.preset, ShortcutPreset.clipStudio);
      expect(keysOf(EditorActionIds.canvasFlipHorizontal, held), [
        'Shift+H',
      ]);
      expect(keysOf(EditorActionIds.redo, held), ['Shift+Y']);
      expect(keysOf(EditorActionIds.toolBrush, held), ['N', 'V']);
    }
  });

  test('what the file brings is the preset\'s change: the window\'s reset '
      'takes it back off', () {
    bindings.importProgramKeys(tvpaint(['ctrl z=Undo']));
    expect(bindings.isOverridden(EditorActionIds.undo), isTrue);

    bindings.resetAll();

    expect(bindings.preset, ShortcutPreset.tvpaint);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
  });

  test('a Mac presses the file\'s Ctrl as ⌘, as it does a preset\'s', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    bindings.importProgramKeys(tvpaint(['ctrl z=Undo']));

    final undo = bindings.activatorsFor(EditorActionIds.undo).single;
    expect((undo.meta, undo.control), (true, false));
  });

  test('what is said: the preset, how many keys came and how many had '
      'nothing to go on', () {
    final said = bindings.importShortcutFile(
      'config.ini',
      utf8.encode('[keyboard]\nctrl z=Undo\na=ZoomShake\nctrl wheel up=ZoomIn'),
    );

    const preset = ShortcutPreset.tvpaint;
    expect(
      said,
      AppText.strings.shortcutFileImported(
        'config.ini',
        AppText.strings.shortcutPresetName(preset.name, preset.label),
        1,
        2,
      ),
    );
  });

  test('a file no keys can be read out of is said so, and changes '
      'nothing', () {
    final said = bindings.importShortcutFile('notes.txt', utf8.encode('메모'));

    expect(said, AppText.strings.shortcutFileUnreadable('notes.txt'));
    expect(bindings.preset, ShortcutPreset.clipStudio);
  });

  test('a row with no keys names none: its action keeps the registry\'s '
      'under the preset', () {
    final rows = presetRows(ShortcutPreset.clipStudio);
    expect(
      rows[EditorActionIds.canvasFlipHorizontal]!.keys,
      isEmpty,
      reason: '⛔fixture premise',
    );

    bindings.setPreset(ShortcutPreset.clipStudio);

    expect(keysOf(EditorActionIds.canvasFlipHorizontal), ['H']);
  });

  test('every TVPaint command a row names has its Japanese name, for the '
      'text the program saves — and there is no name of another', () {
    expect(tvpaintShownNames.keys.toSet(), {
      for (final row in presetRows(ShortcutPreset.tvpaint).values)
        ...row.commands,
    });
  });
}
