
import 'package:flutter/foundation.dart';

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

/// SAVE-1: the save policy (the 2026-07 저장 설계 확정).
///
/// - 🚨**AUTOSAVE SAVES THE PROJECT FILE.** This bullet used to say the
///   opposite — 「the recovery snapshot is the ONLY thing written without
///   an explicit save; the project file changes on a save alone (「저장 안
///   하고 닫기 = 버리기」 stays real)」 — and that had already been
///   overtaken by a decision nobody carried into the comment. 유저
///   2026-09-07: 「기존 결정대로 자동저장이 파일갱신. **그게 싫으면
///   자동저장 off하면된다**고 말했는데 안바꿧나보네」.
///   ⇒ 「저장 안 하고 닫기 = 버리기」 is now a property of
///   [periodicSnapshotMinutes]: null (OFF) and it is literal, a number and
///   the file follows the work every n minutes. The switch is the user's.
class AppSaveSettings {
  const AppSaveSettings({
    this.periodicSnapshotMinutes,
  });

  /// What the clock offers when it is first switched on.
  static const int defaultPeriodicSnapshotMinutes = 10;

  /// 🚨F-1 (유저 2026-08-26): 「자동저장 분 설정은 **공통 슬라이더** 사용해서
  /// **최소 3분, 최대 60분**」. The four chips (5/10/20/30) were a made-up
  /// menu; a range is the honest shape for "how much work may be at risk".
  static const int minPeriodicSnapshotMinutes = 3;
  static const int maxPeriodicSnapshotMinutes = 60;

  /// Minutes of work the app will let pass without saving, or null for
  /// OFF — 🚨F-1: the whole autosave policy is this one number now.
  ///
  /// 유저 2026-08-26: 「**자동저장 on off만 남기고**, 앱 떠날때·손 멈출때
  /// 스냅샷 기능 삭제. 심플하게 **명시적저장 / n분주기 자동저장**만 남김」.
  ///
  /// 🚨★★★**AND IT IS ALSO THE 「저장 안 하고 닫기 = 버리기」 SWITCH.** A
  /// tick saves the PROJECT FILE, so with a number here, closing without
  /// saving keeps everything up to the last tick — the discard rule is
  /// literal only at null. 유저 2026-09-07, settling it: 「기존 결정대로
  /// 자동저장이 파일갱신. **그게 싫으면 자동저장 off하면된다**」. ⛔So this
  /// is not merely「how often」; it is which of the two contracts the user
  /// is working under, and that is why it stays one visible switch.
  ///
  /// ⚠️Two triggers went with F-1, and both were real: leaving the app
  /// (the only warning a mobile OS gives before it stops the process) and
  /// pausing the work. What replaces them is this clock and an explicit
  /// save, which is what was asked for — 「심플하게」. The cost is stated
  /// where it is paid: with autosave OFF, close the app without saving and
  /// the work is gone, on every platform.
  ///
  /// 🔑 Still a CEILING rather than a cadence: a snapshot restarts the
  /// count, so ten minutes means "never more than ten minutes of work at
  /// risk". With one trigger left the two readings coincide, but the
  /// guard's arithmetic is the ceiling's and stays that way.
  final int? periodicSnapshotMinutes;

  // 🪦**`recordingsDirectory` IS GONE, AND SO IS THE FOLDER IT NAMED.** It
  // pointed the take shelf somewhere the user chose — which made the app
  // write to a THIRD location, and 유저 2026-09-08 cut that to two: 「위치를
  // 앱컨테이너/실제파일 이렇게 두군데로만 정리하고싶은거고. 그 외 위치엔
  // 두고싶지않아」. A take is staged like every other carried asset now, so
  // there is no folder left to place. ⛔Exactly the `conformDirectory`
  // reason below, one round later.
  //
  // 🚨And the default it fell back to was worse than a third location: on
  // Windows `%USERPROFILE%/Documents/Anicel` resolves case-insensitively
  // onto the source repository, so takes were landing IN THE REPO — which
  // a `/Recordings/` line in `.gitignore` had been papering over.

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
  }) => AppSaveSettings(
    periodicSnapshotMinutes: identical(periodicSnapshotMinutes, _unset)
        ? this.periodicSnapshotMinutes
        : periodicSnapshotMinutes as int?,
  );

  Map<String, dynamic> toJson() => {
    'periodicSnapshotMinutes': periodicSnapshotMinutes,
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
      // `recordingsDirectory` joins them: READ AND DROPPED. The take shelf
      // it pointed at is gone, so a stored folder is a value with nothing
      // left to configure.
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSaveSettings &&
      other.periodicSnapshotMinutes == periodicSnapshotMinutes;

  @override
  int get hashCode => periodicSnapshotMinutes.hashCode;
}

/// The LIVE save policy (the [AppInput] idiom): the session restores and
/// persists it; the autosave service and the Preferences dialog read it.
abstract final class AppSave {
  static final ValueNotifier<AppSaveSettings> settings =
      ValueNotifier<AppSaveSettings>(const AppSaveSettings());

  /// FNV-1a over [text] — the one hash a derived cache name in the app is
  /// built from, so two of them cannot disagree about what "the same path"
  /// means.
  ///
  /// 🪦It had a sibling, `encodeProjectKey`, that turned a project path
  /// into `basename.<hash>` for the two per-project folders. Both are gone
  /// with the recovery snapshots; the audio conform key is the one caller
  /// left, and it hashes what it actually varies by rather than a path.
  static int pathHash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
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

  // 🪦**`resolveSettingsDirectories` STOOD HERE, AND IT HAD ONE FOLDER TO
  // RESOLVE.** Q-scoped-folder-settings (유저 08-26 「알아서 맡김」): on
  // macOS the sandbox forgets a picked path at relaunch, so a setting that
  // stored only the path stayed on screen while every write quietly
  // failed — it reopened the scope from the stored bookmark at launch.
  // ⛔The LAW survives and applies to the next configurable folder anyone
  // adds: **a stored folder needs its bookmark resolved before the first
  // write, or the setting lies.** What is gone is the only folder that
  // needed it. The export dialog remembers a `lastLocation` the same way,
  // and does not need this because its picker asks again every time — the
  // app never writes there unattended.
}
