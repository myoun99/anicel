import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_body.dart';

/// 🗣️H82 (유저 2026-11-24): 「갤탭에서 tvp브러시 임포트해봣는데 진행창이
/// 안뜨고 갑자기 가져왔다고만 뜸. 다른거도 확인해서 뭐든 임포트면 통일해서
/// 뜨게」 — every file brought into a library is read and made into what it
/// holds behind the app's one wait window, the import window's
/// (`bringBehindTheWaitWindow`), as media, a folder and a project already
/// were (F-53: a wait that says nothing cannot be told from nothing).
///
/// Two doors bring them: the one door every opened, dropped or handed file
/// knocks on (`OpenedFilesDoor.open` — pinned by what it does in
/// `the_one_door_test`), and a library's own ＋, whose pick
/// (`importPickedFile`) brings what it picked behind what its door stands it
/// behind (`brush_preset_library_test`). These are the ＋s' doors, read from
/// source — and the ledger of every place a library's reader is called, so
/// the next door that calls one is caught here and asked where it stands.
void main() {
  String read(String path) => File(path).readAsStringSync();

  // Read through to `async`: a named parameter's `{` would otherwise be
  // taken for the body's.
  for (final (path, head) in [
    (
      'lib/src/ui/workspace/workspace_brush_presets.dart',
      'Future<void> _importAndNotice(',
    ),
    (
      'lib/src/ui/brush/text_tool_settings.dart',
      'Future<void> _bring(BuildContext context, ImportedFonts fonts)',
    ),
  ]) {
    test('$head — ${path.split('/').last} — brings behind the window', () {
      expect(
        sourceBodyOf(
          read(path),
          RegExp('${RegExp.escape(head)}[\\s\\S]*?async'),
        ),
        contains('bringBehindTheWaitWindow('),
      );
    });
  }

  // ⚠️A count changed here is a door added or taken away: a new caller of a
  // reader brings what it reads behind `bringBehindTheWaitWindow` (or hands
  // it to a door that does), and is written in.
  final ledger = <String, Map<String, int>>{
    // The brush library's reader, as the one door hands it a file.
    r'\.importFile\(\(': {'lib/src/ui/editor_workspace.dart': 1},
    // The fonts' — its own ＋ through the pick, and the one door's.
    r'\bimportBytes\(': {
      'lib/src/ui/editor_workspace.dart': 1,
      'lib/src/ui/text/imported_fonts.dart': 2,
    },
    // The brush tips' — its declaration and its ＋.
    r'\bregisterImageBytes\(': {'lib/src/ui/brush/brush_tip_library.dart': 2},
    r'\bimportPaletteFile\(': {
      'lib/src/ui/color/palette_file_import.dart': 1,
      'lib/src/ui/editor_workspace.dart': 1,
    },
    r'\bimportShortcutFiles\(': {
      'lib/src/ui/editor_workspace.dart': 1,
      'lib/src/ui/shortcuts/shortcut_file_import.dart': 1,
    },
    r'\binstallFxPluginFile\(': {
      'lib/src/ui/dialogs/fx_plugin_install_flow.dart': 1,
      'lib/src/ui/editor_workspace.dart': 1,
    },
    // Every ＋ that picks a file itself.
    r'\bimportPickedFile\(': {
      'lib/src/ui/brush/brush_preset_library.dart': 1,
      'lib/src/ui/brush/brush_tip_library.dart': 1,
      'lib/src/ui/brush/picked_file.dart': 1,
      'lib/src/ui/text/imported_fonts.dart': 1,
    },
  };
  final sources = {
    for (final file in dartFilesUnder('lib'))
      file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  };
  for (final MapEntry(key: pattern, value: expected) in ledger.entries) {
    test('$pattern is called where the ledger says, and nowhere else', () {
      final calls = RegExp(pattern);
      expect({
        for (final MapEntry(key: path, value: source) in sources.entries)
          if (calls.allMatches(source).length case final count when count > 0)
            path: count,
      }, expected);
    });
  }
}
