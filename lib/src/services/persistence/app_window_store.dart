import 'app_support_path.dart';
import 'versioned_settings_file.dart';

/// Loads and saves how the app's window stands — whether it is full screen
/// (I-103-Q2, 유저 2026-10-16: on the desktops, remembered for the next
/// run). Editor/app state, not project data — an app-support JSON file
/// beside the UI scale.
///
/// ⚠️Its own file, not the workspace layout's: 「작업공간 배치 초기화」
/// resets the layout, and full screen is the window, not the layout.
class AppWindowStore {
  AppWindowStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() => appSettingsFilePath('window.json');

  static const int version = 1;

  /// Whether the last run left the window full screen, or null when there
  /// is nothing usable on disk.
  Future<bool?> loadFullScreen() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: (json) => json['fullScreen'] is bool
        ? json['fullScreen'] as bool
        : null,
  );

  Future<void> saveFullScreen(bool on) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: {'fullScreen': on},
  );
}
