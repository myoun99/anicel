import '../../services/brush_preset_file_service.dart';
import '../../services/brush_tip_library_service.dart';
import '../../services/color_palette_file_service.dart';
import '../../services/persistence/app_accent_settings_store.dart';
import '../../services/persistence/app_camera_path_settings_store.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../../services/persistence/app_frame_count_settings_store.dart';
import '../../services/persistence/app_frame_grid_settings_store.dart';
import '../../services/persistence/app_input_settings_store.dart';
import '../../services/persistence/app_language_settings_store.dart';
import '../../services/persistence/app_onion_skin_settings_store.dart';
import '../../services/persistence/app_pixel_verb_settings_store.dart';
import '../../services/persistence/app_save_settings_store.dart';
import '../../services/persistence/app_ui_scale_store.dart';
import '../../services/persistence/app_workspace_colors_store.dart';
import '../../services/persistence/audio_sync_settings_store.dart';
import '../../services/persistence/settings_file.dart';
import '../brush/brush_hand_settings_store.dart';
import '../panels/workspace_layout_store.dart';
import '../shortcuts/shortcut_settings_store.dart';
import '../text/app_strings.dart';

/// Who reads a row's settings again once they are put in place — what the
/// app does with them at its start, done again.
enum SettingsReader {
  /// The app-wide settings ([EditorAppSettings.restore]).
  appSettings,

  /// The UI scale, which `main()` reads before the first frame.
  uiScale,

  /// The shortcut bindings ([EditorShortcutBindings.restore]).
  shortcuts,

  /// The workspace's docks and panels.
  layout,

  /// The palettes and recent colours.
  palette,

  /// The brush library, its tips and what the hand left on each brush.
  brushes,

  /// The export window, which reads its settings each time it opens, and
  /// opens on `AppExport.settings` where the file holds none.
  exportWindow,
}

/// One row a settings file brings to the import window (🗣️I-142-Q6:
/// 「임포트 창에 설정 파일의 행으로」): the settings room's [entries] it puts
/// in place, under the name the person knows them by ([label]), and who
/// reads them again ([reader]).
final class SettingsRow {
  const SettingsRow(
    this.id,
    this.entries,
    this.reader,
    this.label,
    this._reads,
  );

  /// What the row is keyed by.
  final String id;

  /// The room's entries the row puts in place ([travellingSettingsEntries]).
  final List<String> entries;

  final SettingsReader reader;

  /// Its name, in the words the person has.
  final String Function(AppStrings strings) label;

  final bool Function(SettingsFile file) _reads;

  /// Whether [file] holds anything of the row — its defaults included.
  bool heldBy(SettingsFile file) => entries.any(
    (entry) =>
        file.atDefaults.contains(entry) ||
        file.documents.containsKey(entry) ||
        [
          ...file.documents.keys,
          ...file.files.keys,
        ].any((name) => name.startsWith('$entry/')),
  );

  /// Whether this build reads what [file] holds of the row. A document a
  /// newer store wrote reads as its store's defaults, so put in place it
  /// would wipe what is here rather than bring what came — it is no answer
  /// a row may give.
  bool readsIn(SettingsFile file) => _reads(file);
}

/// [entry]'s document in [file] is one a store at [version] reads: no newer
/// — an older is the store's to bring forward, as it does its own file.
/// What the file does not hold of it stands in nobody's way.
bool _upTo(SettingsFile file, String entry, int version) =>
    switch (file.documents[entry]) {
      null => true,
      {'version': final int written} => written <= version,
      _ => false,
    };

/// A row of one document, read by a store at [version].
SettingsRow _one(
  String entry,
  int version,
  SettingsReader reader,
  String Function(AppStrings strings) label,
) => SettingsRow(
  entry,
  [entry],
  reader,
  label,
  (file) => _upTo(file, entry, version),
);

/// Every row a settings file may bring, in the order the import window
/// lists them.
///
/// 🗣️I-142-Q9 (유저 2026-10-29): 「설정마다 한 줄 (브러시 셋만 한 줄)」 —
/// one row per entry of the room, but the brushes' three. The brush library
/// names its tips by id, and so does each brush's hand setting, so one put
/// in place without the others points a brush at another tip.
/// `the_settings_rows_hold_every_travelling_entry_test` keeps the rows and
/// the room's entries one list.
final List<SettingsRow> settingsRows = List.unmodifiable([
  _one(
    'input_settings.json',
    AppInputSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.prefsInput,
  ),
  _one(
    'save_settings.json',
    AppSaveSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.prefsAutosave,
  ),
  _one(
    'audio_sync_settings.json',
    AudioSyncSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.prefsAudio,
  ),
  _one(
    'language_settings.json',
    AppLanguageSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.prefsLanguage,
  ),
  _one(
    'ui_scale.json',
    AppUiScaleStore.version,
    SettingsReader.uiScale,
    (s) => s.uiScaleLabel,
  ),
  _one(
    'accent_settings.json',
    AppAccentSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.prefsAccent,
  ),
  _one(
    'workspace_colors.json',
    AppWorkspaceColorsStore.version,
    SettingsReader.appSettings,
    (s) => s.pasteboardTitle,
  ),
  _one(
    'onion_skin_settings.json',
    AppOnionSkinSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.panelOnionSkin,
  ),
  _one(
    'frame_grid_settings.json',
    AppFrameGridSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.blockFrameLinesLabel,
  ),
  _one(
    'frame_count_settings.json',
    AppFrameCountSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.settingsRowFrameCount,
  ),
  _one(
    'camera_path_settings.json',
    AppCameraPathSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.cameraPath,
  ),
  _one(
    'pixel_verb_settings.json',
    AppPixelVerbSettingsStore.version,
    SettingsReader.appSettings,
    (s) => s.tlSharedColourEdit,
  ),
  _one(
    'export_settings.json',
    AppExportSettingsStore.version,
    SettingsReader.exportWindow,
    (s) => s.exExport,
  ),
  _one(
    'workspace_layout.json',
    WorkspaceLayoutStore.layoutVersion,
    SettingsReader.layout,
    (s) => s.settingsRowWorkspaceLayout,
  ),
  _one(
    'color_palette.json',
    ColorPaletteFileService.version,
    SettingsReader.palette,
    (s) => s.panelColorPalette,
  ),
  _one(
    'shortcut_overrides.json',
    ShortcutSettingsStore.version,
    SettingsReader.shortcuts,
    (s) => s.shortcutTitle,
  ),
  SettingsRow(
    'brushes',
    const [
      'brush_presets.json',
      'brush_tips',
      'brush_hand_settings.json',
    ],
    SettingsReader.brushes,
    (s) => s.brBrushesTitle,
    // ⚠️The library reads EXACTLY its own version — any other is replaced
    // by the built-ins on load ([BrushPresetFileService.libraryVersion]).
    (file) =>
        switch (file.documents['brush_presets.json']) {
          null => true,
          {'version': final int written} =>
            written == BrushPresetFileService.libraryVersion,
          _ => false,
        } &&
        _upTo(
          file,
          'brush_tips/index.json',
          BrushTipLibraryService.indexVersion,
        ) &&
        _upTo(
          file,
          'brush_hand_settings.json',
          BrushHandSettingsStore.version,
        ),
  ),
]);
