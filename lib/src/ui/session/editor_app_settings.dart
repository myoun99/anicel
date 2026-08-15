import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

import '../../models/app_language.dart';
import '../../services/input/wintab_pen_service.dart';
import '../../services/persistence/app_accent_settings_store.dart';
import '../../services/persistence/app_input_settings_store.dart';
import '../../services/persistence/app_language_settings_store.dart';
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/app_save_settings_store.dart';
import '../../services/persistence/app_workspace_colors_store.dart';
import '../../services/persistence/audio_sync_settings_store.dart';
import '../input/app_input_settings.dart';
import '../playback/audio_sync_settings.dart';
import '../text/app_strings.dart';
import '../theme/app_accents.dart';
import '../theme/app_theme.dart' show AppColors;
import '../theme/app_workspace_colors.dart';

/// The APP-level settings an editor session restores once at construction and
/// persists on every set: language, accents, workspace colors, input, save and
/// the A/V offset.
///
/// The LIVE values do not live here. They sit on the app-wide notifiers
/// ([AppText.settings], [AppColors.accentSettings],
/// [AppWorkspaceColors.settings], [AppInput.settings], [AppSave.settings]) so
/// that widgets holding no session still read them, and they outlive any one
/// session. What this object owns is the other half: the injectable STORES and
/// the restore/persist path into them.
///
/// [EditorSessionManager] delegates to it and keeps its own API unchanged —
/// callers of `setLanguageSettings`, `audioSyncSettings` and the rest see no
/// difference.
class EditorAppSettings {
  EditorAppSettings({
    AppLanguageSettingsStore? languageSettingsStore,
    AppAccentSettingsStore? accentSettingsStore,
    AppWorkspaceColorsStore? workspaceColorsStore,
    AppInputSettingsStore? inputSettingsStore,
    AppSaveSettingsStore? saveSettingsStore,
    AudioSyncSettingsStore? audioSyncSettingsStore,
  }) : _languageSettingsStore = languageSettingsStore,
       _accentSettingsStore = accentSettingsStore,
       _workspaceColorsStore = workspaceColorsStore,
       _inputSettingsStore = inputSettingsStore,
       _saveSettingsStore = saveSettingsStore,
       _audioSyncSettingsStore = audioSyncSettingsStore;

  /// Starts all six restores, in the order the session started them in.
  ///
  /// Each is fired and not awaited (a missing or corrupt file yields the
  /// defaults), so the session is usable before any of them land.
  void restore() {
    unawaited(_restoreLanguageSettings());
    unawaited(_restoreAccentSettings());
    unawaited(_restoreWorkspaceColors());
    unawaited(_restoreInputSettings());
    unawaited(_restoreSaveSettings());
    unawaited(_restoreAudioSyncSettings());
  }

  // --- Language settings (UI-R10 #7) ----------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppLanguageSettingsStore? _languageSettingsStore;

  /// The program + notation languages — a value-only channel (widgets
  /// subscribe where they read strings; no whole-session notify).
  ///
  /// The notifier itself lives app-wide on [AppText.settings], so canvas
  /// widgets that hold no session still read the chosen language; this is
  /// that same object, not a copy.
  ValueNotifier<AppLanguageSettings> get languageSettings => AppText.settings;

  /// The PROGRAM-language string table, read at call time — for session
  /// verbs that produce user-facing messages and for widgets that already
  /// hold the session.
  AppStrings get uiStrings =>
      AppStrings.of(languageSettings.value.programLanguage);

  Future<void> _restoreLanguageSettings() async {
    final restored = await _languageSettingsStore?.load();
    if (restored != null) {
      languageSettings.value = restored;
    }
  }

  void setLanguageSettings(AppLanguageSettings settings) {
    if (settings == languageSettings.value) {
      return;
    }
    languageSettings.value = settings;
    final store = _languageSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- Accent settings (UI-R22 #5) ------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppAccentSettingsStore? _accentSettingsStore;

  /// The LIVE accents live app-wide on [AppColors.accentSettings] (the
  /// theme root rebuilds off it); the session only restores/persists.
  Future<void> _restoreAccentSettings() async {
    final restored = await _accentSettingsStore?.load();
    if (restored != null) {
      AppColors.accentSettings.value = restored;
    }
  }

  void setAccentSettings(AppAccentSettings settings) {
    if (settings == AppColors.accentSettings.value) {
      return;
    }
    AppColors.accentSettings.value = settings;
    final store = _accentSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- Workspace colors (R28 #9) --------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppWorkspaceColorsStore? _workspaceColorsStore;

  /// The app-level workspace colors are the NEW-PROJECT DEFAULTS now
  /// (R3b): the pasteboard itself became project data — it prints, so it
  /// travels with the project (R28 #9 reversed by the user, 2026-07-29).
  /// This restore keeps the stored default alive for the next project.
  Future<void> _restoreWorkspaceColors() async {
    final restored = await _workspaceColorsStore?.load();
    if (restored != null) {
      AppWorkspaceColors.settings.value = restored;
    }
  }

  /// Remembers a pasteboard choice as the app-level default for the NEXT
  /// project, which is all that remains of the old app-state pasteboard
  /// after the R3b promotion. No-op when unchanged.
  ///
  /// The PROJECT's own pasteboard is written by the session's
  /// `setPasteboardColor`, which is the undoable half of the same verb.
  void rememberPasteboardDefault(int argb) {
    final next = AppWorkspaceColors.settings.value.copyWith(
      pasteboardArgb: argb,
    );
    if (next == AppWorkspaceColors.settings.value) {
      return;
    }
    AppWorkspaceColors.settings.value = next;
    final store = _workspaceColorsStore;
    if (store != null) {
      unawaited(store.save(next));
    }
  }

  // --- Input settings (UI-R22 #6) -------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppInputSettingsStore? _inputSettingsStore;

  Future<void> _restoreInputSettings() async {
    // The Wintab guard decides WHEN the tablet path went dead; persisting
    // that demotion is this side's half. Without it the dead choice
    // reloads on the next launch — with no working pointer to undo it.
    WintabPenService.instance.persistSettings = setInputSettings;
    final restored = await _inputSettingsStore?.load();
    if (restored != null) {
      AppInput.settings.value = restored;
    }
  }

  void setInputSettings(AppInputSettings settings) {
    if (settings == AppInput.settings.value) {
      return;
    }
    AppInput.settings.value = settings;
    final store = _inputSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- Save settings (SAVE-1) -----------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppSaveSettingsStore? _saveSettingsStore;

  Future<void> _restoreSaveSettings() async {
    final restored = await _saveSettingsStore?.load();
    if (restored != null) {
      AppSave.settings.value = restored;
    }
  }

  void setSaveSettings(AppSaveSettings settings) {
    if (settings == AppSave.settings.value) {
      return;
    }
    AppSave.settings.value = settings;
    final store = _saveSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- A/V offset (audio program 2D) ----------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AudioSyncSettingsStore? _audioSyncSettingsStore;

  /// The user's A/V offset — the residual correction for THIS machine's
  /// output path (screen pipeline, Bluetooth, an AV receiver). App state,
  /// not project state: a rig's delay must not travel inside a `.anicel`.
  final ValueNotifier<AudioSyncSettings> audioSyncSettings =
      ValueNotifier<AudioSyncSettings>(AudioSyncSettings.defaults);

  Future<void> _restoreAudioSyncSettings() async {
    final restored = await _audioSyncSettingsStore?.load();
    if (restored != null) {
      audioSyncSettings.value = restored;
    }
  }

  void setAudioSyncSettings(AudioSyncSettings settings) {
    if (settings == audioSyncSettings.value) {
      return;
    }
    audioSyncSettings.value = settings;
    final store = _audioSyncSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  /// [languageSettings] is NOT disposed here: it lives on [AppText],
  /// app-wide, and outlives this session (as the accent settings do). The
  /// A/V offset is this object's own, so it goes.
  void dispose() {
    audioSyncSettings.dispose();
  }
}
