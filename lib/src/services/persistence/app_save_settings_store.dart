import 'versioned_settings_file.dart';

import 'app_save_settings.dart';
import 'app_support_path.dart';

/// Loads and saves the save/autosave policy (SAVE-1). App state — an
/// app-support JSON beside the language/accent/input settings;
/// missing/corrupt files yield the defaults.
class AppSaveSettingsStore {
  AppSaveSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSupportFilePath('save_settings.json');

  static const int version = 1;

  Future<AppSaveSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppSaveSettings.fromJson,
  );

  Future<void> save(AppSaveSettings settings) =>
      saveVersionedSettings(
        filePath: filePath,
        version: version,
        json: settings.toJson(),
      );
}
