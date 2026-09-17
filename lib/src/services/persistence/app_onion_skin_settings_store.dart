import 'versioned_settings_file.dart';

import '../../models/onion_skin_settings.dart';
import 'app_support_path.dart';

/// Loads and saves the onion-skin shape — the pegs, the tints, the mode and
/// what a peg step counts.
///
/// 🚨★★★F-150 (유저 2026-09-16): 「어니언 패널에서 세팅한 값이 **세션으로서
/// 저장안됨. 세션이라기보다 유저설정?**」. It is a user setting: a light
/// table's shape is how this animator works, not something the project
/// holds — so it rides in app support beside the accents and the input
/// settings, and a missing or corrupt file yields the defaults.
///
/// ⛔Which OBJECT owns the live value did not change. `OnionSkin` still
/// holds it because it is the thing that plans with it (ARCH-session-state,
/// 2026-09-16, and that decision is written at the field); this store only
/// puts it back on the way in and writes it on the way out.
class AppOnionSkinSettingsStore {
  AppOnionSkinSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('onion_skin_settings.json');

  static const int version = 1;

  Future<OnionSkinSettings?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: OnionSkinSettings.fromJson,
  );

  Future<void> save(OnionSkinSettings settings) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: settings.toJson(),
  );
}
