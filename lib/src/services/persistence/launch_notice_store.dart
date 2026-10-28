import 'app_support_path.dart';
import 'versioned_settings_file.dart';

/// Where the launch notice remembers what it was told not to show again:
/// the key of the notice a person closed with 「다음부터 표시 안 함」
/// (`LaunchNoticeContent.key`).
///
/// 🗣️유저 2026-10-28: 「앱 실행시 앱 설명 넣고싶어. 다음부터 표시안함버튼
/// 있고. 빌드당 한번기억」 — so what is kept is WHICH notice was dismissed,
/// never whether one was: a build whose notice says something else is
/// shown again, once.
class LaunchNoticeStore {
  LaunchNoticeStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSettingsFilePath('launch_notice.json');

  static const int version = 1;

  /// The key of the notice last dismissed, or null when none was.
  Future<String?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: (json) => json['dismissed'] as String?,
  );

  Future<void> save(String dismissedKey) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: {'dismissed': dismissedKey},
  );
}
