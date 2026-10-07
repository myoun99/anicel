import '../../services/persistence/versioned_settings_file.dart';

import '../../services/persistence/app_support_path.dart';
import 'shortcut_presets.dart';

/// Loads and saves the user's shortcut settings: the preset in use, the keys
/// recorded under each preset ({preset: {actionId: [activator json]}}) and
/// the touch gestures. Editor/app state like the workspace layout: an
/// app-support JSON file; missing or corrupt files simply yield no overrides
/// (the registry defaults win).
class ShortcutSettingsStore {
  ShortcutSettingsStore({String? filePath})
    : filePath = filePath ?? defaultShortcutSettingsFilePath();

  final String filePath;

  static String defaultShortcutSettingsFilePath() =>
      appSettingsFilePath('shortcut_overrides.json');

  /// ↩️1 held ONE set of overrides ({actionId: […]}) — there was one layout,
  /// the registry's. 2 (I-63) holds a set per preset and the preset in use.
  static const int version = 2;

  /// The saved payload in THIS version's shape; null when
  /// missing/corrupt/newer.
  Future<Map<String, Object?>?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: _inThisShape,
  );

  /// A version 1 document's overrides were recorded over the registry's own
  /// keys, which is the anicel preset — so that is whose they are now, and a
  /// key somebody recorded before the presets still presses what it did.
  static Map<String, Object?> _inThisShape(Map<String, dynamic> json) =>
      (json['version'] as int? ?? 0) >= version
      ? json
      : {
          ...json,
          'overrides': {ShortcutPreset.anicel.name: json['overrides']},
        };

  Future<void> save(Map<String, Object?> payload) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: payload,
  );
}
