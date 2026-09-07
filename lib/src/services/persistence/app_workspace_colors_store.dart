import 'versioned_settings_file.dart';

import '../../models/app_workspace_colors.dart';
import 'app_support_path.dart';

/// Loads and saves the workspace surface colors (R28 #9) — the
/// pasteboard color. Editor/app state, not project data: an app-support
/// JSON file beside the accent settings; missing/corrupt files yield the
/// defaults.
class AppWorkspaceColorsStore {
  AppWorkspaceColorsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('workspace_colors.json');

  static const int version = 1;

  Future<AppWorkspaceColors?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: AppWorkspaceColors.fromJson,
  );

  Future<void> save(AppWorkspaceColors settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
