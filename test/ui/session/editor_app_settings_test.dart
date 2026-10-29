import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/app_frame_count_settings.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/frame.dart' show InbetweenMark;
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/pixel_verb_settings.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/services/persistence/app_camera_path_settings_store.dart';
import 'package:anicel/src/services/persistence/app_frame_count_settings_store.dart';
import 'package:anicel/src/services/persistence/app_frame_grid_settings_store.dart';
import 'package:anicel/src/services/persistence/app_input_settings_store.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/app_save_settings_store.dart';
import 'package:anicel/src/services/persistence/app_memory_settings_store.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/services/persistence/app_onion_skin_settings_store.dart';
import 'package:anicel/src/services/persistence/app_pixel_verb_settings_store.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/app_ui_scale.dart';
import 'package:anicel/src/services/persistence/app_ui_scale_store.dart';
import 'package:anicel/src/services/persistence/app_workspace_colors_store.dart';
import 'package:anicel/src/services/persistence/audio_sync_settings_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/models/app_workspace_colors.dart';

import '../../helpers/library_source.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/project_scratch_folder.dart';

/// Every app-level settings family `EditorAppSettings` keeps: each has
/// to be persisted through ITS OWN injected store and read back by the next
/// run.
///
/// Written when the settings block moved out of the session manager. A move
/// refactor passes the existing suite by construction — nothing there
/// constructs a session with all seven stores — so the thing worth asserting is
/// the WIRING. Drop one store from the constructor call, or one restore from
/// `EditorAppSettings.restore()`, and exactly one expectation below dies.
///
/// A RUN here is one settings object and a session on it: the app's shell
/// builds the settings once and every open project shares them (I-7).
void main() {
  // The live values are app-wide and outlive any one session, so every test
  // starts from the product defaults instead of inheriting the last pick.
  void resetAppWideDefaults() {
    AppText.settings.value = const AppLanguageSettings();
    AppColors.accentSettings.value = const AppAccentSettings();
    AppWorkspaceColors.settings.value = const AppWorkspaceColors();
    AppInput.settings.value = const AppInputSettings();
    AppSave.settings.value = const AppSaveSettings();
    AppMemory.settings.value = const AppMemorySettings();
    AppFrameGridSettings.settings.value = const AppFrameGridSettings();
    AppFrameCountSettings.settings.value = const AppFrameCountSettings();
    CameraPathSettings.settings.value = const CameraPathSettings();
    PixelVerbSettings.settings.value = const PixelVerbSettings();
  }

  setUp(resetAppWideDefaults);
  tearDown(resetAppWideDefaults);

  test('every settings family crosses a session boundary through its own '
      'injected store', () async {
    final directory = await Directory.systemTemp.createTemp('qa-app-settings');
    deleteAfterSessionEnds(directory);
    const names = [
      'lang',
      'accent',
      'colors',
      'input',
      'save',
      'memory',
      'av',
      'uiscale',
      'onion',
      'grid',
      'count',
      'campath',
      'pixelverbs',
    ];
    String path(String name) => '${directory.path}/$name.json';

    /// One run: the settings the shell builds and restores once, and a
    /// session on them. The settings are the run's, not the session's, so
    /// the run lets both go.
    EditorSessionManager openRun() {
      final settings = EditorAppSettings(
        languageSettingsStore: AppLanguageSettingsStore(filePath: path('lang')),
        accentSettingsStore: AppAccentSettingsStore(filePath: path('accent')),
        workspaceColorsStore: AppWorkspaceColorsStore(
          filePath: path('colors'),
        ),
        inputSettingsStore: AppInputSettingsStore(filePath: path('input')),
        saveSettingsStore: AppSaveSettingsStore(filePath: path('save')),
        memorySettingsStore: AppMemorySettingsStore(filePath: path('memory')),
        audioSyncSettingsStore: AudioSyncSettingsStore(filePath: path('av')),
        uiScaleStore: AppUiScaleStore(filePath: path('uiscale')),
        onionSkinSettingsStore: AppOnionSkinSettingsStore(
          filePath: path('onion'),
        ),
        frameGridSettingsStore: AppFrameGridSettingsStore(
          filePath: path('grid'),
        ),
        frameCountSettingsStore: AppFrameCountSettingsStore(
          filePath: path('count'),
        ),
        cameraPathSettingsStore: AppCameraPathSettingsStore(
          filePath: path('campath'),
        ),
        pixelVerbSettingsStore: AppPixelVerbSettingsStore(
          filePath: path('pixelverbs'),
        ),
      )..restore();
      addTearDown(settings.dispose);
      return EditorSessionManager(
        initialProject: createDefaultProject(),
        appSettings: settings,
      );
    }

    final first = openRun();
    first.setLanguageSettings(
      const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
        notationLanguage: AppLanguage.fr,
      ),
    );
    first.setAccentSettings(const AppAccentSettings(accent: Color(0xFF123456)));
    first.projectSettings.setPasteboardColor(0xFF204060);
    final penResponse = BrushPressureCurve(const [
      BrushCurvePoint(0, 0),
      BrushCurvePoint(0.5, 0.8),
      BrushCurvePoint(1, 1),
    ]);
    first.setInputSettings(AppInputSettings(pressureCurve: penResponse));
    first.setSaveSettings(
      const AppSaveSettings(periodicSnapshotMinutes: 7),
    );
    first.setMemorySettings(
      const AppMemorySettings(allowanceBytes: 3 << 30),
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
    // 🚨★★★F-150 (유저 2026-09-16): 「어니언 패널에서 세팅한 값이 **세션으로서
    // 저장안됨. 세션이라기보다 유저설정?**」 — the eighth family. Its live
    // value sits on the settings object itself rather than an app-wide
    // notifier (I-7), so the next run's own object is what has to come back
    // carrying it, and no reset is needed below.
    appSettingsOf(first).setOnionSkinSettings(
      const OnionSkinSettings(
        beforePegs: [
          OnionPeg(opacity: 0.9),
          OnionPeg(opacity: 0.5),
          OnionPeg(opacity: 0),
          OnionPeg(opacity: 0),
          OnionPeg(opacity: 0),
          OnionPeg(opacity: 0),
          OnionPeg(opacity: 0),
          OnionPeg(opacity: 0),
        ],
        tintAfter: 0xFF0000FF,
        mode: OnionSkinMode.images,
        step: OnionSkinStep.frames,
        // Not the default (in place, onion-ghosts-in-place-Q2 pending).
        placement: OnionSkinPlacement.onTop,
      ),
    );
    first.setUiScale(1.3);
    // The block frame lines (유저 2026-09-24) — a user setting, app-wide like
    // the accents; ON here because OFF is the default a lost store returns
    // (↩️the other way round until 2026-10-01, 「기본값 off로」). And the mark
    // an unnamed drawing wears beside it (F-489) — the ○, because the ● is
    // the default.
    appSettingsOf(first).setFrameGridSettings(
      const AppFrameGridSettings(
        blockFrameLines: true,
        unnamedMark: InbetweenMark.one,
      ),
    );
    // The count window's entry (I-24-open-entry) and the mark-every window's
    // mark (I-130-Q2) — seconds+frames and a pick, because frames and no
    // pick are what a lost store returns (F-489-Q1).
    appSettingsOf(first).setFrameCountSettings(
      const AppFrameCountSettings(
        lastEntry: FrameCountEntry.secondsPlusFrames,
        lastEveryMark: InbetweenMark.two,
      ),
    );
    // How the canvas shows a camera's path (I-89 ④) — every field off its
    // default, since a lost store returns the defaults.
    appSettingsOf(first).setCameraPathSettings(
      const CameraPathSettings(
        show: CameraPathShow.space,
        range: CameraPathRange.aroundPlayhead,
        tickEvery: 6,
        around: 4,
      ),
    );
    // What the colour edit list's knobs hold (I-13-Q2 = a, 「기억한다」) —
    // every field off its default.
    appSettingsOf(first).setPixelVerbSettings(
      const PixelVerbSettings(
        binarizeThreshold: 179,
        deleteColourTolerance: 4,
        keepColourTolerance: 9,
      ),
    );
    // The saves are fire-and-forget. Waiting on the files rather than on a
    // fixed delay keeps this honest on a machine that is busy building.
    await pollUntil(
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

    // ⚠️Without this reset the second run "restoring" a value would be
    // indistinguishable from the app-wide notifier simply still holding what
    // the first one put there — every assertion below would pass with no
    // store ever read. The A/V offset and the pegs need no reset: they live
    // on each run's own settings object.
    resetAppWideDefaults();

    final second = openRun();
    addTearDown(second.dispose);
    // ⚠️A DEADLINE, not a count of rounds ([waitPatience]). Three hundred
    // rounds of 10ms ran out while a parallel batch filled the machine
    // (09-24, `settings-roundtrip-poll-runs-out-under-load`): the memory
    // allowance was restored late, not never — the same file passed alone.
    // A generous deadline costs nothing when the restores land; it only
    // decides how long a real failure takes to say so. ↩️The deadline was
    // this file's own `_settleUntil`, 30 s, until 2026-10-16.
    await pollUntil(
      () =>
          AppText.settings.value.programLanguage == AppLanguage.ko &&
          AppColors.accentSettings.value.accent == const Color(0xFF123456) &&
          AppWorkspaceColors.settings.value.pasteboardArgb == 0xFF204060 &&
          AppInput.settings.value.pressureCurve == penResponse &&
          AppSave.settings.value.periodicSnapshotMinutes == 7 &&
          AppMemory.settings.value.allowanceBytes == 3 << 30 &&
          AppFrameGridSettings.settings.value.blockFrameLines &&
          AppFrameGridSettings.settings.value.unnamedMark ==
              InbetweenMark.one &&
          AppFrameCountSettings.settings.value.lastEveryMark ==
              InbetweenMark.two &&
          CameraPathSettings.settings.value.tickEvery == 6 &&
          PixelVerbSettings.settings.value.binarizeThreshold == 179 &&
          appSettingsOf(second).audioSyncSettings.value.offset == 42,
    );

    expect(second.languageSettings.value.programLanguage, AppLanguage.ko);
    expect(second.languageSettings.value.notationLanguage, AppLanguage.fr);
    expect(second.uiStrings, AppStrings.of(AppLanguage.ko));
    expect(AppColors.accentSettings.value.accent, const Color(0xFF123456));
    expect(AppWorkspaceColors.settings.value.pasteboardArgb, 0xFF204060);
    expect(AppInput.settings.value.pressureCurve, penResponse);
    expect(AppSave.settings.value.periodicSnapshotMinutes, 7);
    expect(AppMemory.settings.value.allowanceBytes, 3 << 30);
    expect(
      AppFrameGridSettings.settings.value,
      const AppFrameGridSettings(
        blockFrameLines: true,
        unnamedMark: InbetweenMark.one,
      ),
    );
    expect(
      AppFrameCountSettings.settings.value,
      const AppFrameCountSettings(
        lastEntry: FrameCountEntry.secondsPlusFrames,
        lastEveryMark: InbetweenMark.two,
      ),
    );
    expect(
      CameraPathSettings.settings.value,
      const CameraPathSettings(
        show: CameraPathShow.space,
        range: CameraPathRange.aroundPlayhead,
        tickEvery: 6,
        around: 4,
      ),
    );
    expect(
      PixelVerbSettings.settings.value,
      const PixelVerbSettings(
        binarizeThreshold: 179,
        deleteColourTolerance: 4,
        keepColourTolerance: 9,
      ),
    );
    expect(appSettingsOf(second).audioSyncSettings.value.offset, 42);
    expect(appSettingsOf(second).audioSyncSettings.value.micGainDb, 3);
    // The onion's live value is the run's settings object, read through the
    // second session's onion skin — and nothing had to be reset for that to
    // mean something.
    await pollUntil(
      () => second.onionSkin.settings.value.mode == OnionSkinMode.images,
    );
    expect(second.onionSkin.settings.value.beforePegs.first.opacity, 0.9);
    expect(second.onionSkin.settings.value.beforePegs[1].opacity, 0.5);
    expect(second.onionSkin.settings.value.tintAfter, 0xFF0000FF);
    expect(second.onionSkin.settings.value.step, OnionSkinStep.frames);
    expect(
      second.onionSkin.settings.value.placement,
      OnionSkinPlacement.onTop,
    );
    expect(
      second.onionSkin.settings.value.beforePegs.length,
      OnionSkinSettings.maxPegs,
      reason: '⛔every slot exists — the panel draws all of them',
    );
  });

  /// I-7 (유저 2026-09-26: 여러 프로젝트를 탭으로) — every open project is a
  /// session of its own, and they all read the app's ONE settings object.
  group('open projects share one settings object', () {
    test('a peg set from one tab is the other tab\'s too, and closing a tab '
        'leaves the settings alive', () {
      final settings = EditorAppSettings();
      addTearDown(settings.dispose);
      final a = EditorSessionManager(
        initialProject: createDefaultProject(),
        appSettings: settings,
      );
      final b = EditorSessionManager(
        initialProject: createDefaultProject(),
        appSettings: settings,
      );
      addTearDown(b.dispose);

      settings.setOnionSkinSettings(
        const OnionSkinSettings(mode: OnionSkinMode.images),
      );
      expect(identical(a.onionSkin.settings, b.onionSkin.settings), isTrue);
      expect(b.onionSkin.settings.value.mode, OnionSkinMode.images);

      a.dispose();
      // A released notifier throws on a write in debug — the one the shell
      // still hands the other tabs has to be alive.
      settings.setAudioSyncSettings(const AudioSyncSettings(offset: 7));
      settings.setOnionSkinSettings(const OnionSkinSettings());
      expect(b.onionSkin.settings.value.mode, isNot(OnionSkinMode.images));
    });

    test('a session on the app\'s settings reads no file — only the one '
        'restore the shell made', () async {
      final directory = await Directory.systemTemp.createTemp('qa-one-read');
      deleteAfterSessionEnds(directory);
      final store = _CountingLanguageStore('${directory.path}/lang.json');
      final settings = EditorAppSettings(languageSettingsStore: store)
        ..restore();
      addTearDown(settings.dispose);
      await settings.languageRestored;
      expect(store.loads, 1, reason: 'premise: the shell\'s one restore');

      for (var tab = 0; tab < 3; tab += 1) {
        final session = EditorSessionManager(
          initialProject: createDefaultProject(),
          appSettings: settings,
        );
        addTearDown(session.dispose);
      }
      await Future<void>.delayed(Duration.zero);

      expect(
        store.loads,
        1,
        reason: 'a restore per tab re-reads every file and writes the '
            'app-wide values back over a change whose save had not landed',
      );
    });
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
    // ⛔Rounds, not a time: under load fewer of them fit in a time, and a
    // window that sees less passes what it is there to catch. ↩️It was
    // 100 ms of the machine's until 2026-10-16.
    for (var round = 0; round < 10; round += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(session.languageSettings.value, const AppLanguageSettings());
    expect(AppColors.accentSettings.value, const AppAccentSettings());
    expect(AppWorkspaceColors.settings.value, const AppWorkspaceColors());
    expect(appSettingsOf(session).audioSyncSettings.value, AudioSyncSettings.defaults);
  });

  // I-142: a settings file put in place brings its UI scale — read again
  // from its file, as `main()` reads it before the first frame.
  test('the UI scale is read again from its file, and the next set that '
      'changes nothing writes nothing', () async {
    final directory = await Directory.systemTemp.createTemp('qa-ui-scale');
    deleteAfterSessionEnds(directory);
    final store = AppUiScaleStore(filePath: '${directory.path}/ui.json');
    final settings = EditorAppSettings(uiScaleStore: store);
    addTearDown(settings.dispose);
    addTearDown(() => AppUiScale.value.value = AppUiScale.defaultScale);
    await store.save(1.3);

    await settings.rereadUiScale();

    expect(AppUiScale.value.value, 1.3);
    await store.save(0.7);
    settings.setUiScale(1.3);
    expect(await store.load(), 0.7, reason: 'held as read: nothing to write');
  });

  /// ⛔**THE PANEL MUST NOT WRITE THE NOTIFIER.** 🧪A mutant that put
  /// `onionSkin.settings.value = next` back in the workspace tab SURVIVED the
  /// behaviour test above — of course it did: that test calls the setter
  /// itself. And a panel that writes the live value directly is EXACTLY the
  /// bug 유저 reported (「세팅한 값이 저장안됨」): the setting works all
  /// session and is gone on the next launch.
  test('the onion panel changes through the setter, never the notifier', () {
    final source = librarySource('lib/src/ui/workspace/workspace_tabs.dart');
    expect(
      source,
      contains('setOnionSkinSettings('),
      reason: 'the panel\'s onChanged goes through the persisting setter',
    );
    expect(
      source,
      isNot(contains('onionSkin.settings.value =')),
      reason:
          '⛔a direct write publishes and saves NOTHING — it is the shape of '
          'F-150 itself',
    );
  });
}

/// A language store that counts its reads — the witness that a session on
/// the app's settings restores nothing of its own.
class _CountingLanguageStore extends AppLanguageSettingsStore {
  _CountingLanguageStore(String filePath) : super(filePath: filePath);

  int loads = 0;

  @override
  Future<AppLanguageSettings?> load() {
    loads += 1;
    return super.load();
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
