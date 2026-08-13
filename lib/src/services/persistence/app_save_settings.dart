import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_support_path.dart';

/// SAVE-1: the save/recovery policy (the 2026-07 저장 설계 확정).
///
/// - The recovery snapshot is the ONLY thing written without an explicit
///   save — the project file changes on a save alone ("저장 안 하고 닫기 =
///   버리기" stays real).
/// - It lives in the app's own support folder. It used to sit beside the
///   project with a setting to move it, which put a project-sized write
///   into whatever cloud folder the project was in and scattered siblings
///   around a file that is becoming a single document. Nothing to
///   configure now, so nothing to configure wrong.
/// - REC1-B2: never-saved projects record onto a visible take shelf
///   (`<app documents>/Recordings` by default) instead of the hidden OS
///   temp; a custom folder is a desktop-only choice.
class AppSaveSettings {
  const AppSaveSettings({
    this.lifecycleSnapshotEnabled = true,
    this.pauseSnapshotEnabled = true,
    this.periodicSnapshotMinutes,
    this.recordingsDirectory,
    this.conformDirectory,
  });

  /// What the interval offers when the user first switches the clock on.
  /// Ten minutes rather than the old five: the clock is a ceiling on
  /// unprotected work now, and pauses already cover everything shorter.
  static const int defaultPeriodicSnapshotMinutes = 10;

  /// Whether leaving the app snapshots (default on).
  ///
  /// The cheapest of the three by a distance — it runs when the app is on
  /// its way out, so nobody is drawing — and on mobile it is the only
  /// warning the OS gives before it kills the process. Switchable because
  /// the user asked for all three to be, not because turning it off is a
  /// sensible thing to want.
  final bool lifecycleSnapshotEnabled;

  /// Whether a pause in the work is worth a snapshot (default on).
  final bool pauseSnapshotEnabled;

  /// Minutes of work the app will let pass without a snapshot, or null for
  /// "only when you pause" (the default).
  ///
  /// The five-minute clock this replaces was removed because each tick
  /// adopted every cel's file ref, so the next manual save could no longer
  /// find its own work and rewrote the project whole. The overlay adopts
  /// nothing now and writes a delta, so a clock is affordable again — and
  /// a long focused stretch is exactly what a pause-only trigger cannot
  /// cover, because it never pauses.
  ///
  /// 🔑 Read as a CEILING, not a cadence: any snapshot, from any trigger,
  /// restarts the count. Ten minutes means "never more than ten minutes of
  /// work at risk", not "write every ten minutes" — otherwise a pause at
  /// 9:50 and a tick at 10:00 write the same bytes twice.
  final int? periodicSnapshotMinutes;

  /// Where a never-saved project's voice takes land; null/empty = the
  /// app documents `Recordings` folder.
  final String? recordingsDirectory;

  /// Where audio conforms are cached; null/empty = the app support folder.
  ///
  /// This exists to place them on a PARTICULAR DEVICE'S disk — out of a
  /// cloud-synced folder, onto an SD card, onto a fast drive — because a
  /// conform is around twelve times the size of its source and used to sit
  /// beside the project, which meant it synced with it. It is NOT a way to
  /// share a cache between machines: that trade spends gigabytes of
  /// transfer to save minutes of CPU.
  final String? conformDirectory;

  static const Object _unset = Object();

  AppSaveSettings copyWith({
    bool? lifecycleSnapshotEnabled,
    bool? pauseSnapshotEnabled,
    Object? periodicSnapshotMinutes = _unset,
    Object? recordingsDirectory = _unset,
    Object? conformDirectory = _unset,
  }) => AppSaveSettings(
    lifecycleSnapshotEnabled:
        lifecycleSnapshotEnabled ?? this.lifecycleSnapshotEnabled,
    pauseSnapshotEnabled: pauseSnapshotEnabled ?? this.pauseSnapshotEnabled,
    periodicSnapshotMinutes: identical(periodicSnapshotMinutes, _unset)
        ? this.periodicSnapshotMinutes
        : periodicSnapshotMinutes as int?,
    recordingsDirectory: identical(recordingsDirectory, _unset)
        ? this.recordingsDirectory
        : recordingsDirectory as String?,
    conformDirectory: identical(conformDirectory, _unset)
        ? this.conformDirectory
        : conformDirectory as String?,
  );

  Map<String, dynamic> toJson() => {
    'lifecycleSnapshotEnabled': lifecycleSnapshotEnabled,
    'pauseSnapshotEnabled': pauseSnapshotEnabled,
    'periodicSnapshotMinutes': periodicSnapshotMinutes,
    'recordingsDirectory': recordingsDirectory,
    'conformDirectory': conformDirectory,
  };

  /// `sidecarDirectory` left by an older build is READ AND DROPPED — the
  /// location is fixed now, and a setting that outlives its feature is a
  /// value the next reader has to work out is dead.
  ///
  /// The two older names ARE carried, because they still mean something:
  /// `autosaveEnabled` was the single switch over every trigger, and the
  /// closest thing it now names is the pause; `autosaveIntervalMinutes`
  /// was a clock a build in between dropped, and a user who had set one
  /// should get it back rather than silently start from the default.
  /// A non-positive interval means "off", the same thing null means, so a
  /// 0 from anywhere cannot become a clock that fires continuously.
  static AppSaveSettings fromJson(Map<String, dynamic> json) {
    final recordings = json['recordingsDirectory'];
    final conforms = json['conformDirectory'];
    final interval =
        json['periodicSnapshotMinutes'] ?? json['autosaveIntervalMinutes'];
    final legacyEnabled = json['autosaveEnabled'] as bool?;
    return AppSaveSettings(
      lifecycleSnapshotEnabled:
          json['lifecycleSnapshotEnabled'] as bool? ?? true,
      pauseSnapshotEnabled:
          json['pauseSnapshotEnabled'] as bool? ?? legacyEnabled ?? true,
      periodicSnapshotMinutes: interval is int && interval > 0
          ? interval
          : null,
      recordingsDirectory: recordings is String && recordings.isNotEmpty
          ? recordings
          : null,
      conformDirectory: conforms is String && conforms.isNotEmpty
          ? conforms
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSaveSettings &&
      other.lifecycleSnapshotEnabled == lifecycleSnapshotEnabled &&
      other.pauseSnapshotEnabled == pauseSnapshotEnabled &&
      other.periodicSnapshotMinutes == periodicSnapshotMinutes &&
      other.recordingsDirectory == recordingsDirectory &&
      other.conformDirectory == conformDirectory;

  @override
  int get hashCode => Object.hash(
    lifecycleSnapshotEnabled,
    pauseSnapshotEnabled,
    periodicSnapshotMinutes,
    recordingsDirectory,
    conformDirectory,
  );
}

/// The LIVE save policy (the [AppInput] idiom): the session restores and
/// persists it; the autosave service and the Preferences dialog read it.
abstract final class AppSave {
  static final ValueNotifier<AppSaveSettings> settings =
      ValueNotifier<AppSaveSettings>(const AppSaveSettings());

  /// Where [projectFilePath]'s crash-recovery snapshot lives: inside the
  /// app's own support folder, never beside the project.
  ///
  /// It used to sit next to the `.anicel`, with a setting to move it, and
  /// both of those are gone. Beside-the-file dropped a project-sized write
  /// into whatever cloud-synced folder the project was in; and the format
  /// is becoming a single file, whose whole point is that the app stops
  /// scattering siblings around it. The support folder is also the one
  /// place the app can always write without asking an OS for permission —
  /// which is what makes a recovery snapshot dependable on iPad.
  /// Redirected under FLUTTER_TEST, like every other store that resolves
  /// an app-support path: tests reach this through the production save and
  /// open wiring, and without the redirect a test run would drop snapshots
  /// into the real user's folder and read the ones left there.
  static String recoveryPathFor(String projectFilePath) {
    final name = encodeRecoveryFileName(projectFilePath);
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return '${Directory.systemTemp.path.replaceAll('\\', '/')}'
          '/qa_test_recovery_$pid/$name';
    }
    return appSupportFilePath('Recovery/$name');
  }

  /// Every place a recovery snapshot for [projectFilePath] may be found.
  ///
  /// The second entry is where releases before this one wrote theirs, kept
  /// so a crash that happened on the old build is still offered after the
  /// update. A snapshot written into a CUSTOM directory by an old build is
  /// unreachable — the setting that named it is gone, and there is nothing
  /// left to reconstruct the path from.
  static List<String> recoveryCandidatesFor(String projectFilePath) => [
    recoveryPathFor(projectFilePath),
    '$projectFilePath.autosave',
  ];

  /// The NEWEST existing recovery snapshot among the candidates, or null.
  static String? newestExistingRecoveryFor(String projectFilePath) {
    String? newest;
    DateTime? newestModified;
    for (final candidate in recoveryCandidatesFor(projectFilePath)) {
      final file = File(candidate);
      if (!file.existsSync()) {
        continue;
      }
      final modified = file.lastModifiedSync();
      if (newestModified == null || modified.isAfter(newestModified)) {
        newest = candidate;
        newestModified = modified;
      }
    }
    return newest;
  }

  /// `basename.<fnv1a32-of-full-path>.autosave` — stable across runs,
  /// filesystem-safe, and collision-resistant across folders.
  static String encodeRecoveryFileName(String projectFilePath) =>
      '${encodeProjectKey(projectFilePath)}.autosave';

  /// `basename.<fnv1a32-of-full-path>` — the app container's name for
  /// [projectFilePath].
  ///
  /// The hash is what keeps two projects called `C-045.anicel` in different
  /// works from sharing one anything now that per-project state lands in
  /// common folders. Every such folder derives its name here rather than
  /// re-deriving the hash, so a recovery snapshot and a conform cache can
  /// never disagree about which project they belong to.
  static String encodeProjectKey(String projectFilePath) {
    final normalized = projectFilePath.replaceAll('\\', '/');
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final base = normalized.split('/').last;
    return '$base.${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// Where [projectFilePath]'s audio conforms are cached.
  ///
  /// Defaults into the app support folder; [AppSaveSettings.conformDirectory]
  /// overrides the ROOT, and the per-project folder underneath it is still
  /// derived here — a user picking a drive should not also have to keep two
  /// projects of the same name apart.
  ///
  /// Conforms used to live in `<project>.assets/Conformed`, which put a
  /// twelve-times-the-source cache inside whatever folder the project was
  /// in, synced it to whatever cloud that folder belonged to, and made the
  /// `.anicel` grow a sibling that the single-file format exists to remove.
  ///
  /// Only the DEFAULT root is redirected under FLUTTER_TEST: a configured
  /// root was named explicitly and is used as given, which is what a test
  /// that sets one is asking for.
  static String conformDirectoryFor(String projectFilePath) =>
      '$conformRootDirectory/${encodeProjectKey(projectFilePath)}';

  /// The folder every project's conform cache sits under — what
  /// Preferences shows, and the one place that decides where the cache
  /// root is.
  static String get conformRootDirectory {
    final configured = settings.value.conformDirectory;
    if (configured != null && configured.isNotEmpty) {
      return configured.replaceAll('\\', '/');
    }
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return '${Directory.systemTemp.path.replaceAll('\\', '/')}'
          '/qa_test_conform_$pid';
    }
    return appSupportFilePath('Conformed');
  }
}
