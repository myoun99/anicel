import 'versioned_settings_file.dart';

import '../../models/app_language.dart';
import 'app_support_path.dart';

/// Loads and saves the two language settings (UI-R10 #7). Editor/app
/// state, not project data — an app-support JSON file next to the
/// workspace layout; missing/corrupt files yield the defaults.
class AppLanguageSettingsStore {
  AppLanguageSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSupportFilePath('language_settings.json');

  static const int version = 1;

  Future<AppLanguageSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppLanguageSettings.fromJson,
  );

  Future<void> save(AppLanguageSettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
