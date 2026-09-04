import '../../services/persistence/versioned_settings_file.dart';

import '../../services/persistence/app_support_path.dart';

/// Loads and saves the user's shortcut overrides ({actionId: [activator
/// json]}). Editor/app state like the workspace layout: an app-support
/// JSON file; missing or corrupt files simply yield no overrides (the
/// registry defaults win).
class ShortcutSettingsStore {
  ShortcutSettingsStore({String? filePath})
    : filePath = filePath ?? defaultShortcutSettingsFilePath();

  final String filePath;

  static String defaultShortcutSettingsFilePath() =>
      appSupportFilePath('shortcut_overrides.json');

  static const int version = 1;

  /// The saved overrides payload; null when missing/corrupt/newer.
  Future<Map<String, Object?>?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: (json) => json,
  );

  Future<void> save(Map<String, Object?> payload) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: payload,
  );
}
