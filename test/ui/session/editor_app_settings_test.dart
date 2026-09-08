import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/services/persistence/app_input_settings_store.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/app_save_settings_store.dart';
import 'package:anicel/src/services/persistence/app_ui_scale_store.dart';
import 'package:anicel/src/services/persistence/app_workspace_colors_store.dart';
import 'package:anicel/src/services/persistence/audio_sync_settings_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/models/app_workspace_colors.dart';

/// The seven app-level settings families the session hands to
/// `EditorAppSettings`: each has to be persisted through ITS OWN injected
/// store and read back by the next session.
///
/// Written when the settings block moved out of the session manager. A move
/// refactor passes the existing suite by construction — nothing there
/// constructs a session with all seven stores — so the thing worth asserting is
/// the WIRING. Drop one store from the constructor call, or one restore from
/// `EditorAppSettings.restore()`, and exactly one expectation below dies.
void main() {
  // The live values are app-wide and outlive any one session, so every test
  // starts from the product defaults instead of inheriting the last pick.
  void resetAppWideDefaults() {
    AppText.settings.value = const AppLanguageSettings();
    AppColors.accentSettings.value = const AppAccentSettings();
    AppWorkspaceColors.settings.value = const AppWorkspaceColors();
    AppInput.settings.value = const AppInputSettings();
    AppSave.settings.value = const AppSaveSettings();
  }

  setUp(resetAppWideDefaults);
  tearDown(resetAppWideDefaults);

  test('every settings family crosses a session boundary through its own '
      'injected store', () async {
    final directory = await Directory.systemTemp.createTemp('qa-app-settings');
    addTearDown(() => directory.delete(recursive: true));
    const names = ['lang', 'accent', 'colors', 'input', 'save', 'av', 'uiscale'];
    String path(String name) => '${directory.path}/$name.json';

    EditorSessionManager openSession() => EditorSessionManager(
      initialProject: createDefaultProject(),
      languageSettingsStore: AppLanguageSettingsStore(filePath: path('lang')),
      accentSettingsStore: AppAccentSettingsStore(filePath: path('accent')),
      workspaceColorsStore: AppWorkspaceColorsStore(filePath: path('colors')),
      inputSettingsStore: AppInputSettingsStore(filePath: path('input')),
      saveSettingsStore: AppSaveSettingsStore(filePath: path('save')),
      audioSyncSettingsStore: AudioSyncSettingsStore(filePath: path('av')),
      uiScaleStore: AppUiScaleStore(filePath: path('uiscale')),
    );

    final first = openSession();
    first.setLanguageSettings(
      const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
        notationLanguage: AppLanguage.fr,
      ),
    );
    first.setAccentSettings(const AppAccentSettings(accent: Color(0xFF123456)));
    first.projectSettings.setPasteboardColor(0xFF204060);
    first.setInputSettings(
      const AppInputSettings(
        pressureCurveGamma: 1.5,
      ),
    );
    first.setSaveSettings(
      const AppSaveSettings(periodicSnapshotMinutes: 7),
    );
    appSettingsOf(first).setAudioSyncSettings(
      const AudioSyncSettings(offset: 42, micGainDb: 3),
    );
    // R11, and ⚠️only the WRITE half crosses the boundary: the UI scale is
    // restored in `main()` before `runApp` rather than by the session, so
    // the second session below does not read it back. Deleting the
    // `store.save` in `EditorAppSettings.setUiScale` was green until this
    // line existed — the setting could have stopped persisting entirely
    // while the Preferences row went on looking like it worked.
    first.setUiScale(1.25);
    // The saves are fire-and-forget. Waiting on the files rather than on a
    // fixed delay keeps this honest on a machine that is busy building.
    await _settleUntil(
      () => names.every((name) => File(path(name)).existsSync()),
    );
    for (final name in names) {
      expect(
        File(path(name)).existsSync(),
        isTrue,
        reason: '$name never reached its store',
      );
    }
    first.dispose();

    // ⚠️Without this reset the second session "restoring" a value would be
    // indistinguishable from the app-wide notifier simply still holding what
    // the first one put there — every assertion below would pass with no
    // store ever read. The A/V offset needs no reset: it is per-session.
    resetAppWideDefaults();

    final second = openSession();
    addTearDown(second.dispose);
    await _settleUntil(
      () =>
          AppText.settings.value.programLanguage == AppLanguage.ko &&
          AppColors.accentSettings.value.accent == const Color(0xFF123456) &&
          AppWorkspaceColors.settings.value.pasteboardArgb == 0xFF204060 &&
          AppInput.settings.value.pressureCurveGamma == 1.5 &&
          AppSave.settings.value.periodicSnapshotMinutes == 7 &&
          appSettingsOf(second).audioSyncSettings.value.offset == 42,
    );

    expect(second.languageSettings.value.programLanguage, AppLanguage.ko);
    expect(second.languageSettings.value.notationLanguage, AppLanguage.fr);
    expect(second.uiStrings, AppStrings.of(AppLanguage.ko));
    expect(AppColors.accentSettings.value.accent, const Color(0xFF123456));
    expect(AppWorkspaceColors.settings.value.pasteboardArgb, 0xFF204060);
    expect(AppInput.settings.value.pressureCurveGamma, 1.5);
    expect(AppSave.settings.value.periodicSnapshotMinutes, 7);
    expect(appSettingsOf(second).audioSyncSettings.value.offset, 42);
    expect(appSettingsOf(second).audioSyncSettings.value.micGainDb, 3);
  });

  test('a set that changes nothing notifies nobody — the guard the seven '
      'families share', () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final settings = appSettingsOf(session);

    var languageNotifications = 0;
    void countLanguage() => languageNotifications += 1;
    AppText.settings.addListener(countLanguage);
    addTearDown(() => AppText.settings.removeListener(countLanguage));

    var colorNotifications = 0;
    void countColors() => colorNotifications += 1;
    AppWorkspaceColors.settings.addListener(countColors);
    addTearDown(
      () => AppWorkspaceColors.settings.removeListener(countColors),
    );

    const picked = AppLanguageSettings(programLanguage: AppLanguage.ja);
    settings.setLanguageSettings(picked);
    settings.setLanguageSettings(picked);
    settings.rememberPasteboardDefault(0xFF112233);
    settings.rememberPasteboardDefault(0xFF112233);

    expect(
      languageNotifications,
      1,
      reason: '⛔The unchanged guard is not an optimization: these '
          'notifiers are app-wide, so firing on a value that did not '
          'change rebuilds the whole app, and the write behind it is a '
          'disk touch per step of a slider drag',
    );
    expect(
      colorNotifications,
      1,
      reason: 'the pasteboard default rides the same walk — seven '
          'settings wrote it out before it was one method',
    );
    expect(AppText.settings.value, picked, reason: 'the pick still landed');
    expect(AppWorkspaceColors.settings.value.pasteboardArgb, 0xFF112233);
  });

  test('a session with no stores keeps the in-memory defaults', () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await _settleUntil(() => false, rounds: 10);

    expect(session.languageSettings.value, const AppLanguageSettings());
    expect(AppColors.accentSettings.value, const AppAccentSettings());
    expect(AppWorkspaceColors.settings.value, const AppWorkspaceColors());
    expect(appSettingsOf(session).audioSyncSettings.value, AudioSyncSettings.defaults);
  });
}

/// Polls [done] instead of sleeping a fixed span: it returns the moment the
/// asynchronous restores land, and still gives up rather than hanging when
/// they never do (the assertion after it names which one).
Future<void> _settleUntil(bool Function() done, {int rounds = 300}) async {
  for (var i = 0; i < rounds && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// The collaborator that owns the laws above, under its OWN name.
///
/// 🚨`tool/mutation_run.dart` picks the tests that will witness a mutation by
/// asking which tests IMPORT the file. Round 8 carved ~50 collaborators out of
/// `EditorSessionManager` and every pin still arrived through the session, so
/// 63 of the 71 files under `lib/src/ui/session/` reported UNNAMED and the
/// campaign skipped exactly the code that round wrote. ⛔Widening the runner to
/// transitive reachability was tried and reverted (one small file drew 390
/// namers); a collaborator that holds a law gets a test that names it instead.
EditorAppSettings appSettingsOf(EditorSessionManager session) => session.appSettings;
