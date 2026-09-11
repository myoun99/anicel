import 'app_memory_settings.dart';
import 'app_support_path.dart';
import 'versioned_settings_file.dart';

/// Where [AppMemorySettings] lives between runs — the save settings'
/// store, for the memory tab.
class AppMemorySettingsStore {
  AppMemorySettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('memory_settings.json');

  static const int version = 1;

  Future<AppMemorySettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppMemorySettings.fromJson,
  );

  Future<void> save(AppMemorySettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
