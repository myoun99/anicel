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
    this.periodicSnapshotMinutes,
    this.recordingsDirectory,
    this.conformDirectory,
  });

  /// What the clock offers when it is first switched on.
  static const int defaultPeriodicSnapshotMinutes = 10;

  /// 🚨F-1 (유저 2026-08-26): 「자동저장 분 설정은 **공통 슬라이더** 사용해서
  /// **최소 3분, 최대 60분**」. The four chips (5/10/20/30) were a made-up
  /// menu; a range is the honest shape for "how much work may be at risk".
  static const int minPeriodicSnapshotMinutes = 3;
  static const int maxPeriodicSnapshotMinutes = 60;

  /// Minutes of work the app will let pass without a snapshot, or null for
  /// OFF — 🚨F-1: the whole autosave policy is this one number now.
  ///
  /// 유저 2026-08-26: 「**자동저장 on off만 남기고**, 앱 떠날때·손 멈출때
  /// 스냅샷 기능 삭제. 심플하게 **명시적저장 / n분주기 자동저장**만 남김」.
  ///
  /// ⚠️Two triggers went with that, and both were real: leaving the app
  /// (the only warning a mobile OS gives before it stops the process) and
  /// pausing the work. What replaces them is this clock and an explicit
  /// save, which is what was asked for — 「심플하게」. The cost is stated
  /// where it is paid: close the app without saving and the work since the
  /// last tick is gone, on every platform.
  ///
  /// 🔑 Still a CEILING rather than a cadence: a snapshot restarts the
  /// count, so ten minutes means "never more than ten minutes of work at
  /// risk". With one trigger left the two readings coincide, but the
  /// guard's arithmetic is the ceiling's and stays that way.
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
    Object? periodicSnapshotMinutes = _unset,
    Object? recordingsDirectory = _unset,
    Object? conformDirectory = _unset,
  }) => AppSaveSettings(
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
    'periodicSnapshotMinutes': periodicSnapshotMinutes,
    'recordingsDirectory': recordingsDirectory,
    'conformDirectory': conformDirectory,
  };

  /// `sidecarDirectory` left by an older build is READ AND DROPPED — the
  /// location is fixed now, and a setting that outlives its feature is a
  /// value the next reader has to work out is dead.
  ///
  /// `autosaveIntervalMinutes` is still carried: it was a clock a build in
  /// between dropped, and a user who had set one should get it back rather
  /// than silently start from the default. A non-positive interval means
  /// "off", the same thing null means, so a 0 from anywhere cannot become
  /// a clock that fires continuously.
  ///
  /// 🚨F-1: `lifecycleSnapshotEnabled`, `pauseSnapshotEnabled` and the
  /// older `autosaveEnabled` are now READ AND DROPPED like
  /// `sidecarDirectory` before them — their triggers are gone, so a value
  /// that outlives its feature is a number the next reader has to work out
  /// is dead. What survives is the clock alone.
  static AppSaveSettings fromJson(Map<String, dynamic> json) {
    final recordings = json['recordingsDirectory'];
    final conforms = json['conformDirectory'];
    final interval =
        json['periodicSnapshotMinutes'] ?? json['autosaveIntervalMinutes'];
    return AppSaveSettings(
      // F-1: clamped into the slider's range. Nothing could have written
      // outside it — the chips this replaces were 5/10/20/30 — but a
      // stored number is a stranger's number, and a slider whose value
      // sits off its own track is an assert waiting for a settings file.
      periodicSnapshotMinutes: interval is int && interval > 0
          ? interval.clamp(
              minPeriodicSnapshotMinutes,
              maxPeriodicSnapshotMinutes,
            )
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
      other.periodicSnapshotMinutes == periodicSnapshotMinutes &&
      other.recordingsDirectory == recordingsDirectory &&
      other.conformDirectory == conformDirectory;

  @override
  int get hashCode => Object.hash(
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
      // ONE stat, not exists-then-mtime: the legacy beside-the-file
      // candidate lives in the user's (possibly cloud-synced) folder, and a
      // file a sync client prunes between the two calls would throw out of
      // the open flow before its try. statSync never throws — a vanished or
      // unreadable candidate simply reports notFound.
      final stat = FileStat.statSync(candidate);
      if (stat.type == FileSystemEntityType.notFound) {
        continue;
      }
      final modified = stat.modified;
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
    final base = normalized.split('/').last;
    return '$base.${pathHash(normalized).toRadixString(16).padLeft(8, '0')}';
  }

  /// FNV-1a over [text] — the one hash every derived cache name in the app
  /// is built from, so two of them cannot disagree about what "the same
  /// path" means.
  static int pathHash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// The folder the conform cache sits under — what Preferences shows, and
  /// the one place that decides where the cache root is.
  ///
  /// Conforms used to live in `<project>.assets/Conformed`, which put a
  /// twelve-times-the-source cache inside whatever folder the project was
  /// in, synced it to whatever cloud that folder belonged to, and made the
  /// `.anicel` grow a sibling that the single-file format exists to remove.
  ///
  /// Only the DEFAULT root is redirected under FLUTTER_TEST: a configured
  /// root was named explicitly and is used as given, which is what a test
  /// that sets one is asking for.
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
