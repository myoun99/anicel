import 'versioned_settings_file.dart';

import '../../models/app_frame_grid_settings.dart';
import 'app_support_path.dart';

/// Loads and saves how the frame grid is drawn — a user setting in app
/// support beside the workspace colours; a missing or corrupt file yields
/// the defaults.
class AppFrameGridSettingsStore {
  AppFrameGridSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('frame_grid_settings.json');

  static const int version = 1;

  Future<AppFrameGridSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppFrameGridSettings.fromJson,
  );

  Future<void> save(AppFrameGridSettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
