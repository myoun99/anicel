import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_documents.dart';
import 'app_support_path.dart';
import 'folder_grant.dart';
import 'session_scratch.dart';

/// A user-chosen folder plus the token that reopens it after a relaunch
/// on the scoped platforms (Q-scoped-folder-settings, 유저 08-26 「알아서
/// 맡김」 → A: bookmarks ride along, the project-grants machinery reused).
///
/// ONE value on purpose, not two parallel fields: a bookmark written
/// beside its path can drift — a copyWith that moves the path and keeps
/// the token is a grant for somewhere else, silently. Travelling
/// together makes that unrepresentable.
///
/// On Windows/Linux/Android the [bookmark] is simply null — a real path
/// keeps working on its own there, exactly like the project grants.
@immutable
class GrantedDirectory {
  const GrantedDirectory({required this.path, this.bookmark});

  final String path;
  final String? bookmark;

  /// A settings file's spelling: the bare path when there is no token
  /// (byte-identical to what older builds wrote), a map when there is.
  Object toJson() =>
      bookmark == null ? path : {'path': path, 'bookmark': bookmark};

  /// Reads both spellings; null for anything else (an older build's
  /// reader treats the map as absent and falls back to the default —
  /// a folder setting, not data, so that costs a re-pick at worst).
  static GrantedDirectory? fromJson(Object? json) {
    if (json is String && json.isNotEmpty) {
      return GrantedDirectory(path: json.replaceAll('\\', '/'));
    }
    if (json is Map) {
      final path = json['path'];
      final bookmark = json['bookmark'];
      if (path is String && path.isNotEmpty) {
        return GrantedDirectory(
          path: path.replaceAll('\\', '/'),
          bookmark: bookmark is String && bookmark.isNotEmpty
              ? bookmark
              : null,
        );
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is GrantedDirectory &&
      other.path == path &&
      other.bookmark == bookmark;

  @override
  int get hashCode => Object.hash(path, bookmark);
}

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

  /// Where a never-saved project's voice takes land; null = the app
  /// documents `Recordings` folder.
  final GrantedDirectory? recordingsDirectory;

  // 🪦**`conformDirectory` IS GONE.** It let the user place the conform
  // cache on a PARTICULAR DEVICE'S disk — out of a cloud folder, onto an
  // SD card — because a conform is ~12× its source and the cache was an
  // unbounded pile that lived across runs. Both halves of that reason have
  // been taken away: a conform now waits in the RUN'S room and moves into
  // the project file at the next save ([AppSave.conformRootDirectory]), so
  // there is no pile to place. ⛔A setting that outlives its feature is a
  // value the next reader has to work out is dead — the same reason
  // `sidecarDirectory` was read and dropped below.

  static const Object _unset = Object();

  AppSaveSettings copyWith({
    Object? periodicSnapshotMinutes = _unset,
    Object? recordingsDirectory = _unset,
  }) => AppSaveSettings(
    periodicSnapshotMinutes: identical(periodicSnapshotMinutes, _unset)
        ? this.periodicSnapshotMinutes
        : periodicSnapshotMinutes as int?,
    recordingsDirectory: identical(recordingsDirectory, _unset)
        ? this.recordingsDirectory
        : recordingsDirectory as GrantedDirectory?,
  );

  Map<String, dynamic> toJson() => {
    'periodicSnapshotMinutes': periodicSnapshotMinutes,
    'recordingsDirectory': recordingsDirectory?.toJson(),
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
      // Both spellings: the bare path older builds wrote, or the
      // path+bookmark map this build writes on scoped platforms.
      recordingsDirectory: GrantedDirectory.fromJson(
        json['recordingsDirectory'],
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSaveSettings &&
      other.periodicSnapshotMinutes == periodicSnapshotMinutes &&
      other.recordingsDirectory == recordingsDirectory;

  @override
  int get hashCode => Object.hash(
    periodicSnapshotMinutes,
    recordingsDirectory,
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
  static String recoveryPathFor(String projectFilePath) =>
      '${recoveryDirectory()}/${encodeRecoveryFileName(projectFilePath)}';

  /// The one folder recovery snapshots live in — what the Preferences
  /// list enumerates and the abandoned-snapshot sweep walks.
  static String recoveryDirectory() =>
      testRedirectedAppSupportPath('Recovery', sandbox: 'recovery');

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

  /// REC1-B2: the take shelf — where a never-saved project's voice takes
  /// land. A folder ordinary file managers show (`Recordings` under the
  /// app documents home, the DAW convention), NOT the hidden OS temp: a
  /// discarded session leaves its takes findable. Nothing ever moves off
  /// the shelf — takes are carried, so the save absorbs their bytes into
  /// the archive from wherever they sit. A custom shelf is a desktop-only
  /// setting.
  ///
  /// It sits HERE, beside [conformRootDirectory], because it is the same
  /// law: a configured folder wins, otherwise a default under a root this
  /// class already knows. It used to live in `app_documents.dart`, which
  /// made that file — the leaf everything else in this folder reaches for —
  /// import these settings, and that was the whole of an import loop
  /// (documents -> settings -> grant -> documents).
  static String get recordingsRootDirectory {
    final configured = settings.value.recordingsDirectory;
    if (configured != null) {
      return configured.path;
    }
    return '${appDocumentsDirectory()}/Recordings';
  }

  /// Where a conform waits until a save absorbs it — **the one place that
  /// decides**, which is what makes the decision reversible.
  ///
  /// Conforms used to live in `<project>.assets/Conformed`, which put a
  /// twelve-times-the-source pile inside whatever folder the project was
  /// in, synced it to whatever cloud that folder belonged to, and made the
  /// `.anicel` grow a sibling that the single-file format exists to remove.
  /// They then moved to a container folder of their own with a size bound,
  /// a collector and a root the user could point anywhere.
  ///
  /// 🚨★★★**NOW IT IS THE RUN'S 이사대기, AND THAT IS A LIFETIME, NOT A
  /// LOCATION.** A conform is decoded PCM waiting to move into the project
  /// file at the next save — the same sentence carried media already had —
  /// so it belongs in the same room, with the same ending: the save takes
  /// it in, and the room goes when the run does. That is what let the
  /// collector, the 2GB bound and the root setting all go: there is
  /// nothing left to accumulate and so nothing to reclaim.
  ///
  /// ⚠️**The bound was doing real work and it is worth knowing what
  /// replaced it.** It existed because 「nobody was collecting any of it」
  /// and on an iPad the container is neither visible nor reachable, so
  /// 「it just grows」 meant 「until the device is full」. A run's room
  /// cannot grow past one session, and the launch sweep takes the rooms of
  /// runs that ended — so the unbounded pile is gone by construction
  /// rather than by a number.
  ///
  /// 🔒**To put it back in the container** (유저 2026-09-07 said that may
  /// happen: 「컨폼파일을 나중에 프로젝트파일에서 앱컨테이너로 뺄 가능성이
  /// 존재해」): change THIS getter and nothing else. Every conform address
  /// is derived from it through [ConformCacheLayout].
  static String get conformRootDirectory => SessionScratch.stagedFolder();

  /// Re-establishes the settings folders' grants for THIS run, answering
  /// the settings value the caller should store when a folder moved — or
  /// null when nothing changed.
  ///
  /// Q-scoped-folder-settings (유저 08-26 「알아서 맡김」 → A): on macOS
  /// the sandbox forgets a picked path at relaunch, so a setting that
  /// stored only the path stayed on screen while every write quietly
  /// failed. Resolving the bookmark reopens the scope (the same machinery
  /// as the project grants) and follows a folder the user renamed.
  ///
  /// A bookmark that will not resolve leaves the stored value UNTOUCHED —
  /// unavailable is not deleted (the provider may simply not be signed in
  /// yet), and the path still names what the user meant.
  static Future<AppSaveSettings?> resolveSettingsDirectories() async {
    final current = settings.value;
    Future<GrantedDirectory?> resolve(GrantedDirectory? directory) async {
      final token = directory?.bookmark;
      if (token == null) {
        return directory;
      }
      final grant = await FolderPicker.resolveBookmark(token);
      final path = grant.path;
      if (!grant.isGranted || path == null) {
        return directory;
      }
      return GrantedDirectory(path: path, bookmark: grant.bookmark ?? token);
    }

    final recordings = await resolve(current.recordingsDirectory);
    if (recordings == current.recordingsDirectory) {
      return null;
    }
    return current.copyWith(recordingsDirectory: recordings);
  }
}
