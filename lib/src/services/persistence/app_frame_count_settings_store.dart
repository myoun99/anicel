import 'versioned_settings_file.dart';

import '../../models/app_frame_count_settings.dart';
import 'app_support_path.dart';

/// Loads and saves which way a frame count was last typed — a user setting
/// in app support beside the frame grid's; a missing or corrupt file yields
/// the defaults.
class AppFrameCountSettingsStore {
  AppFrameCountSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('frame_count_settings.json');

  static const int version = 1;

  Future<AppFrameCountSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppFrameCountSettings.fromJson,
  );

  Future<void> save(AppFrameCountSettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
