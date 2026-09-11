import 'versioned_settings_file.dart';

import '../../models/app_input_settings.dart';
import 'app_support_path.dart';

/// Loads and saves the pointer-input policy (UI-R22 #6). Editor/app
/// state — an app-support JSON file beside the language/accent settings;
/// missing/corrupt files yield the defaults.
class AppInputSettingsStore {
  AppInputSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('input_settings.json');

  /// 2: the wheel click's old default — PAN — leaves version-1 files.
  static const int version = 2;

  Future<AppInputSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: _fromStored,
  );

  /// 🗣️I-15 (유저 2026-09-11): 「휠클릭은 왜 남아있는거지? 잔재 삭제해주고」.
  /// A version-1 file wrote every mapping out, so a wheel PAN in it is the
  /// old default sitting in the file rather than a choice anyone made — it
  /// goes with the default. From version 2 the file keeps what is mapped.
  static AppInputSettings _fromStored(Map<String, dynamic> json) {
    final settings = AppInputSettings.fromJson(json);
    if ((json['version'] as int? ?? 0) >= 2 ||
        settings.canvasWheelClick.action != CanvasPointerAction.pan) {
      return settings;
    }
    return settings.copyWith(
      canvasWheelClick: const CanvasPointerMapping(
        action: CanvasPointerAction.none,
      ),
    );
  }

  Future<void> save(AppInputSettings settings) =>
      saveVersionedSettings(
        filePath: filePath,
        version: version,
        json: settings.toJson(),
      );
}
