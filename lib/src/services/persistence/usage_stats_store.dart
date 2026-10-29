import 'app_support_path.dart';
import 'versioned_settings_file.dart';

/// The person's answer to the usage statistics (I-70), as the settings file
/// keeps it — and, with a yes, what the device keeps for counting.
sealed class UsageStatsAnswer {
  const UsageStatsAnswer();
}

/// No: nothing is sent, and nothing is kept.
final class UsageStatsOff extends UsageStatsAnswer {
  const UsageStatsOff();
}

/// Yes, with the UTC days this device was used on within the last 28
/// (`UsageStats`).
final class UsageStatsOn extends UsageStatsAnswer {
  const UsageStatsOn(this.activeDays);

  final List<int> activeDays;
}

/// Where the usage statistics (I-70) keep the person's answer and the
/// record they count from.
///
/// ⚖️THE FILE IS THE ANSWER (2026-10-29, this lane): 🗣️유저 08:1x chose
/// 「따로 묻는 작은 창」, asked ONCE — so the file has to tell a person never
/// asked from one who said no. A file is written by an answer alone (the
/// question's, or the switch in Preferences ▸ System) and by the record a
/// yes keeps, so no file — or one this build cannot read — is "never
/// answered", and the file's `enabled` is the answer: ONE answer in ONE
/// place, no second "asked" flag beside it to disagree with it.
///
/// 🗣️I-70-Q3 (유저 2026-10-29): 「기본 꺼짐」 — never answered is OFF too.
///
/// ⚠️The record lives ON THIS DEVICE ALONE and only while the switch is on:
/// [UsageStatsOff] holds none, so "off with a record" cannot come back from
/// the file even if one was written.
class UsageStatsStore {
  UsageStatsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() => appSettingsFilePath('usage_stats.json');

  static const int version = 1;

  /// The answer the person gave — or null while they have given none: no
  /// file, or a file this build cannot read.
  Future<UsageStatsAnswer?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: (json) => json['enabled'] as bool
        ? UsageStatsOn([
            for (final day in json['activeDays'] as List) day as int,
          ])
        : const UsageStatsOff(),
  );

  Future<void> save(UsageStatsAnswer answer) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: switch (answer) {
      UsageStatsOn(:final activeDays) => {
        'enabled': true,
        'activeDays': activeDays,
      },
      UsageStatsOff() => {'enabled': false},
    },
  );
}
