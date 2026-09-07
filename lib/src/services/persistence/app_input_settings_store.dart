import 'versioned_settings_file.dart';

import '../../models/app_input_settings.dart';
import 'app_support_path.dart';

/// Loads and saves the pointer-input policy (UI-R22 #6). Editor/app
/// state — an app-support JSON file beside the language/accent settings;
/// missing/corrupt files yield the defaults.
class AppInputSettingsStore {
  AppInputSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('input_settings.json');

  static const int version = 1;

  Future<AppInputSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppInputSettings.fromJson,
  );

  Future<void> save(AppInputSettings settings) =>
      saveVersionedSettings(
        filePath: filePath,
        version: version,
        json: settings.toJson(),
      );
}
