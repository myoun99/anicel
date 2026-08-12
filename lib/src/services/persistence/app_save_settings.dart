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
    this.autosaveEnabled = true,
    this.autosaveIntervalMinutes = 5,
    this.recordingsDirectory,
  });

  final bool autosaveEnabled;

  /// Minutes between dirty-session snapshots (clamped ≥ 1 on use).
  final int autosaveIntervalMinutes;

  /// Where a never-saved project's voice takes land; null/empty = the
  /// app documents `Recordings` folder.
  final String? recordingsDirectory;

  static const Object _unset = Object();

  AppSaveSettings copyWith({
    bool? autosaveEnabled,
    int? autosaveIntervalMinutes,
    Object? recordingsDirectory = _unset,
  }) => AppSaveSettings(
    autosaveEnabled: autosaveEnabled ?? this.autosaveEnabled,
    autosaveIntervalMinutes:
        autosaveIntervalMinutes ?? this.autosaveIntervalMinutes,
    recordingsDirectory: identical(recordingsDirectory, _unset)
        ? this.recordingsDirectory
        : recordingsDirectory as String?,
  );

  Map<String, dynamic> toJson() => {
    'autosaveEnabled': autosaveEnabled,
    'autosaveIntervalMinutes': autosaveIntervalMinutes,
    'recordingsDirectory': recordingsDirectory,
  };

  /// A stored `sidecarDirectory` from an older build is READ AND DROPPED —
  /// the location is not configurable any more, and carrying the key
  /// forward would let a stale path outlive the feature that used it.
  static AppSaveSettings fromJson(Map<String, dynamic> json) {
    final recordings = json['recordingsDirectory'];
    return AppSaveSettings(
      autosaveEnabled: json['autosaveEnabled'] as bool? ?? true,
      autosaveIntervalMinutes:
          (json['autosaveIntervalMinutes'] as num?)?.round() ?? 5,
      recordingsDirectory: recordings is String && recordings.isNotEmpty
          ? recordings
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSaveSettings &&
      other.autosaveEnabled == autosaveEnabled &&
      other.autosaveIntervalMinutes == autosaveIntervalMinutes &&
      other.recordingsDirectory == recordingsDirectory;

  @override
  int get hashCode => Object.hash(
    autosaveEnabled,
    autosaveIntervalMinutes,
    recordingsDirectory,
  );
}

/// The LIVE save policy (the [AppInput] idiom): the session restores and
/// persists it; the autosave service and the Preferences dialog read it.
abstract final class AppSave {
  static final ValueNotifier<AppSaveSettings> settings =
      ValueNotifier<AppSaveSettings>(const AppSaveSettings());

  static Duration get autosaveInterval =>
      Duration(minutes: settings.value.autosaveIntervalMinutes.clamp(1, 1440));

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
  /// filesystem-safe, and collision-resistant across folders. The hash is
  /// what keeps two projects called `C-045.anicel` in different works from
  /// sharing one snapshot now that they land in a common folder.
  static String encodeRecoveryFileName(String projectFilePath) {
    final normalized = projectFilePath.replaceAll('\\', '/');
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final base = normalized.split('/').last;
    return '$base.${hash.toRadixString(16).padLeft(8, '0')}.autosave';
  }
}
