import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// A saved language that comes back only when the test says so.
class _LateKoreanStore extends AppLanguageSettingsStore {
  _LateKoreanStore() : super(filePath: 'unused');

  final gate = Completer<void>();

  @override
  Future<AppLanguageSettings?> load() async {
    await gate.future;
    return const AppLanguageSettings(programLanguage: AppLanguage.ko);
  }

  @override
  Future<void> save(AppLanguageSettings settings) async {}
}

/// The first library a launch makes waits for the SAVED language.
///
/// The settings restore is fired and not awaited, and so were the brush
/// libraries' loads — two reads racing. The built-ins are named as they are
/// made and are stored text from then on (brush-preset-names-language-Q1:
/// 「만들 때 그 언어로 적는다」), so a library that won the race would keep its
/// brushes in whatever the app said before the language landed.
void main() {
  testWidgets('the built-ins wait for the saved language to be named', (
    tester,
  ) async {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Real file IO only inside runAsync — the testWidgets clock is fake, and
    // an awaited read never completes on it.
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('late_language'),
    ))!;
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _LateKoreanStore();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(
          presetFileService: BrushPresetFileService(
            filePath: '${directory.path}/brush_presets.json',
          ),
          tipLibraryService: BrushTipLibraryService(
            directoryPath: '${directory.path}/tips',
          ),
          languageSettingsStore: store,
        ),
      ),
    );

    // Long enough for a library that did NOT wait to finish its reads: each
    // read completes in real time and its continuation runs on a pump.
    for (var turn = 0; turn < 10; turn += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    store.gate.complete();

    List<BrushPreset>? presets;
    for (var tries = 0; tries < 40 && presets == null; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final panels = find.byType(BrushPresetPanel);
      if (panels.evaluate().isNotEmpty) {
        final shown = tester.widget<BrushPresetPanel>(panels.first).presets;
        if (shown.isNotEmpty) {
          presets = shown;
        }
      }
    }

    expect(presets, isNotNull, reason: 'the library never landed');
    expect(
      presets!.firstWhere((preset) => preset.id.value == 'builtin-g-pen').name,
      'G펜',
    );
  });
}
