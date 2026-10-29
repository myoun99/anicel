import '../usage_stats/aptabase_client.dart' show AptabaseSession;
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

/// Yes, with the UTC days this device was used on within the last 28, the
/// events still to send and the session the last went in (`UsageStats`).
final class UsageStatsOn extends UsageStatsAnswer {
  const UsageStatsOn(this.activeDays, [this.queue = const [], this.session]);

  final List<int> activeDays;

  /// Each as it goes over the wire, its moment and session already fixed
  /// (`AptabaseStamped`), oldest first.
  final List<Map<String, Object?>> queue;

  /// The session the last event went in and when it began, for a run
  /// opened before its 55 minutes are out to go on in (I-70-Q10 · Q13) —
  /// null before any event.
  final AptabaseSession? session;
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
/// ⚠️The record and the queue live ON THIS DEVICE ALONE and only while the
/// switch is on: [UsageStatsOff] holds neither, so "off with a record" — or
/// with events still to send — cannot come back from the file even if one
/// was written.
///
/// ⚖️THE QUEUE SHARES THE FILE WITH THE RECORD (2026-10-29, this lane): a
/// day is recorded in the same write that queues its event, so a day is
/// never counted without its event kept, nor kept twice — and the file is
/// already bound to this machine (`settingsBoundToThisMachine`).
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
        ? UsageStatsOn(
            [for (final day in json['activeDays'] as List) day as int],
            [
              for (final event in json['queue'] as List)
                event as Map<String, Object?>,
            ],
            _sessionOf(json['session']),
          )
        : const UsageStatsOff(),
  );

  Future<void> save(UsageStatsAnswer answer) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: switch (answer) {
      UsageStatsOn(:final activeDays, :final queue, :final session) => {
        'enabled': true,
        'activeDays': activeDays,
        'queue': queue,
        if (session != null)
          'session': {
            'id': session.id,
            'startedAt': session.startedAt.toUtc().toIso8601String(),
          },
      },
      UsageStatsOff() => {'enabled': false},
    },
  );

  /// The kept session — or none to go on in, which a file without one, or
  /// with one this build cannot read, also is.
  static AptabaseSession? _sessionOf(Object? json) {
    if (json case {'id': final String id, 'startedAt': final String at}) {
      final startedAt = DateTime.tryParse(at);
      if (startedAt != null) {
        return (id: id, startedAt: startedAt);
      }
    }
    return null;
  }
}
