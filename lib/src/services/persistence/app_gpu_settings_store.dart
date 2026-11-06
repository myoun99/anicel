import '../../models/app_gpu_settings.dart';
import 'app_support_path.dart';
import 'versioned_settings_file.dart';

/// Where [AppGpuSettings] lives between runs — and where the Windows runner
/// reads it before the engine is made (`windows/runner/main.cpp`).
class AppGpuSettingsStore {
  AppGpuSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('gpu_settings.json');

  static const int version = 1;

  Future<AppGpuSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppGpuSettings.fromJson,
  );

  Future<void> save(AppGpuSettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
