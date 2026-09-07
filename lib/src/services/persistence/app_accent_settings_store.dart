import 'versioned_settings_file.dart';

import '../../models/app_accents.dart';
import 'app_support_path.dart';

/// Loads and saves the two program accents (UI-R22 #5). Editor/app
/// state, not project data — an app-support JSON file beside the
/// language settings; missing/corrupt files yield the defaults.
class AppAccentSettingsStore {
  AppAccentSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('accent_settings.json');

  static const int version = 1;

  Future<AppAccentSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppAccentSettings.fromJson,
  );

  Future<void> save(AppAccentSettings settings) =>
      saveVersionedSettings(
        filePath: filePath,
        version: version,
        json: settings.toJson(),
      );
}
