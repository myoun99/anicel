import 'app_support_path.dart';
import 'versioned_settings_file.dart';

/// Where the usage statistics (I-70) keep the person's answer and the
/// record they count from: whether to send at all, and the UTC days this
/// device was used on within the last 28 (`UsageStats`).
///
/// 🗣️I-70-Q3 (유저 2026-10-29): 「안내 창에서 묻고 기본 꺼짐」 — so a missing
/// file is OFF, as is one that cannot be read.
///
/// ⚠️The record lives ON THIS DEVICE ALONE and only while the switch is on:
/// [load] hands back no days for a device that is off, so "off with a
/// record" cannot come back from the file even if one was written.
class UsageStatsStore {
  UsageStatsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() => appSettingsFilePath('usage_stats.json');

  static const int version = 1;

  /// The days recorded while on — or null when the person has not turned
  /// it on (no file, a file that says off, a file this build cannot read).
  Future<List<int>?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: (json) => (json['enabled'] as bool? ?? false)
        ? [for (final day in json['activeDays'] as List) day as int]
        : null,
  );

  /// On with [activeDays], or off when they are null.
  Future<void> save(List<int>? activeDays) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: {
      'enabled': activeDays != null,
      'activeDays': activeDays ?? const <int>[],
    },
  );
}
