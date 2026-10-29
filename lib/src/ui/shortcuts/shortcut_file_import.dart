import 'dart:convert';
import 'dart:typed_data';

import '../../services/persistence/settings_file.dart';
import '../../services/shortcuts/program_keymap.dart';
import '../brush/picked_file.dart' show PickedFile;
import '../text/app_strings.dart';
import 'editor_shortcut_bindings.dart';
import 'shortcut_presets.dart';
import 'shortcut_settings_store.dart' show shortcutPresetsInSettingsFile;

/// Brings the shortcut files [files] into [bindings] (I-107) — what to say
/// of them: a line for each new preset, and one for each file no keys could
/// be read out of.
///
/// 🗣️I-107-Q1 (유저 2026-10-18, 「기타」): 「가져올땐 새 프리셋으로서
/// 등록」 — a program's files make a preset of the user's, which comes
/// into use, named for the program's preset and the files. ONE program's
/// files that come in together make one: CLIP STUDIO PAINT keeps its
/// menus' keys in one file and its tools' in another.
/// ↩️The keys were put on the program's own preset until that answer
/// (추천 a, built while the question waited).
/// Our own file (I-142) holds a preset whole, and each it holds comes in
/// as a new one by the same answer.
List<String> importShortcutFiles(
  EditorShortcutBindings bindings,
  List<PickedFile> files,
) {
  final said = <String>[];
  final byProgram = <KeymapProgram, List<(String, ProgramKeymap)>>{};
  for (final (:name, :bytes) in files) {
    if (name.toLowerCase().endsWith('.$anicelShortcutExtension')) {
      said.addAll(_presetsOfOurFile(bindings, name, bytes));
    } else if (readShortcutFile(name, bytes) case final keymap?) {
      byProgram.putIfAbsent(keymap.program, () => []).add((name, keymap));
    } else {
      said.add(AppText.strings.shortcutFileUnreadable(name));
    }
  }
  for (final MapEntry(key: program, value: read) in byProgram.entries) {
    final base = presetOf(program);
    final keymaps = [for (final (_, keymap) in read) keymap];
    final preset = bindings.presetOfFiles(
      '${AppText.strings.shortcutPresetName(base.name, base.label)} — '
      '${[for (final (name, _) in read) name].join(' · ')}',
      base,
      keymaps,
    );
    final counted = countFileKeys(keymaps);
    said.add(
      AppText.strings.shortcutFileImported(
        preset.name,
        counted.taken,
        counted.skipped,
      ),
    );
  }
  return said;
}

/// Our own shortcut file [name] (I-142), holding [bytes]: each preset it
/// holds a new one of the user's, the last coming into use — a line for
/// each, or one saying it could not be read.
List<String> _presetsOfOurFile(
  EditorShortcutBindings bindings,
  String name,
  Uint8List bytes,
) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return [AppText.strings.shortcutFileUnreadable(name)];
  }
  final read = shortcutPresetsInSettingsFile(text, keeps: bindings.keeps);
  if (read == null || read.isEmpty) {
    return [AppText.strings.shortcutFileUnreadable(name)];
  }
  return [
    for (final preset in read)
      AppText.strings.shortcutPresetBrought(
        bindings.duplicatePreset(preset, preset.name).name,
      ),
  ];
}
