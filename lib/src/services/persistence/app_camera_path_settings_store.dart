import 'versioned_settings_file.dart';

import '../../models/camera_path_settings.dart';
import 'app_support_path.dart';

/// Loads and saves how the canvas shows a camera's path — a user setting in
/// app support beside the frame grid's; a missing or corrupt file yields
/// the defaults.
class AppCameraPathSettingsStore {
  AppCameraPathSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('camera_path_settings.json');

  static const int version = 1;

  Future<CameraPathSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: CameraPathSettings.fromJson,
  );

  Future<void> save(CameraPathSettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
