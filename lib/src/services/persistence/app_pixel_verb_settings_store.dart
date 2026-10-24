import 'versioned_settings_file.dart';

import '../../models/pixel_verb_settings.dart';
import 'app_support_path.dart';

/// Loads and saves what the colour edit list's pixel verbs run with — a
/// user setting in app support beside the camera path's; a missing or
/// corrupt file yields the defaults.
class AppPixelVerbSettingsStore {
  AppPixelVerbSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('pixel_verb_settings.json');

  static const int version = 1;

  Future<PixelVerbSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: PixelVerbSettings.fromJson,
  );

  Future<void> save(PixelVerbSettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
