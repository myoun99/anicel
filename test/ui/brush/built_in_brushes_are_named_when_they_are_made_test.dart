// THE BUILT-INS ARE NAMED IN THE LANGUAGE THE APP SPEAKS WHEN THEY ARE MADE,
// and are the user's text from then on.
//
// 유저 2026-09-15 (brush-preset-names-language-Q1): 「만들 때 그 언어로
// 적는다」. The cost the answer named is pinned too: switching the language
// afterwards renames nothing that was stored.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/ui/brush/brush_preset_library.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_tip_library.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import '../../helpers/temp_dir.dart';

void main() {
  void speak(AppLanguage language) =>
      AppText.settings.value = AppLanguageSettings(programLanguage: language);

  /// A temp directory per test, and the language put back after it.
  Directory Function() scratch(String prefix) {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(prefix);
    });
    tearDown(() async {
      AppText.settings.value = const AppLanguageSettings();
      deleteTempQuietly(directory);
    });
    return () => directory;
  }

  group('the brush library', () {
    final temp = scratch('built_in_brush_names');

    BrushPresetLibrary libraryAt(String name) => BrushPresetLibrary(
      fileService: BrushPresetFileService(
        filePath: '${temp().path}/$name.json',
      ),
    );
    String presetName(BrushPresetLibrary library, String id) =>
        library.presets.firstWhere((preset) => preset.id.value == id).name;
    String groupName(BrushPresetLibrary library, String id) =>
        library.groups.firstWhere((group) => group.id.value == id).name;

    test('made while the app speaks Korean, the built-ins are named in '
        'Korean', () async {
      speak(AppLanguage.ko);
      final library = libraryAt('fresh');
      addTearDown(library.dispose);
      await library.load();

      expect(presetName(library, 'builtin-g-pen'), 'G펜');
      expect(presetName(library, 'builtin-blending-stump'), '찰필');
      expect(groupName(library, 'builtin-watercolor-group'), '수채');
    });

    test("made in English, they keep the defaults' own words", () async {
      final library = libraryAt('english');
      addTearDown(library.dispose);
      await library.load();

      expect(
        library.presets.map((preset) => preset.name),
        defaultBrushPresets.map((preset) => preset.name),
      );
      expect(
        library.groups.map((group) => group.name),
        defaultBrushGroups.map((group) => group.name),
      );
    });

    test('reset while the app speaks Japanese writes Japanese names', () async {
      final library = libraryAt('reset');
      addTearDown(library.dispose);
      await library.load();

      speak(AppLanguage.ja);
      library.resetToDefaults();

      expect(presetName(library, 'builtin-maru-pen'), '丸ペン');
      expect(groupName(library, 'builtin-ink-group'), 'ペン');
    });

    test('⛔switching the language afterwards renames nothing that was '
        'stored — the cost the answer named', () async {
      final path = '${temp().path}/stored.json';
      speak(AppLanguage.ko);
      final first = BrushPresetLibrary(
        fileService: BrushPresetFileService(filePath: path),
      );
      addTearDown(first.dispose);
      await first.load();
      first.resetToDefaults();
      await _untilTheFileSays(path, 'G펜');

      speak(AppLanguage.fr);
      final second = BrushPresetLibrary(
        fileService: BrushPresetFileService(filePath: path),
      );
      addTearDown(second.dispose);
      await second.load();

      expect(presetName(second, 'builtin-g-pen'), 'G펜');
    });

    test('a brush saved while the app speaks Korean is named in Korean', () async {
      final library = libraryAt('saved');
      addTearDown(library.dispose);
      await library.load();

      speak(AppLanguage.ko);
      final preset = library.saveCurrent(BrushSettings(size: 5));

      expect(preset.name, '프리셋 ${library.presets.length}');
    });
  });

  group('the tips', () {
    final temp = scratch('built_in_tip_names');

    test('made while the app speaks French, the generated tips are named in '
        'French', () async {
      speak(AppLanguage.fr);
      final library = BrushTipLibrary(
        service: BrushTipLibraryService(directoryPath: temp().path),
      );
      addTearDown(library.dispose);
      await library.load();

      String tip(String id) =>
          library.tips.firstWhere((entry) => entry.id == id).name;
      expect(tip('builtin-chalk'), 'Craie');
      expect(tip('builtin-flake'), 'Flocon');
    });
  });

  testWidgets('a new group is offered under the name the app speaks', (
    tester,
  ) async {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    speak(AppLanguage.ko);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: SingleChildScrollView(
              child: BrushPresetPanel(
                presets: const [],
                onGroupCreated: (name) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-new-group')),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey<String>('brush-preset-group-new-text-field'),
    );
    expect(tester.widget<TextField>(field).controller!.text, '새 그룹');
  });
}

/// Waits for a fire-and-forget write to put [text] on disk, and FAILS rather
/// than waits forever when it never does.
Future<void> _untilTheFileSays(String path, String text) async {
  final file = File(path);
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (await file.exists() && (await file.readAsString()).contains(text)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('$path never said $text');
}
