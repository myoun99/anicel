import 'dart:async';
import 'dart:io';

import 'app_save_settings.dart';
import 'sweep_old_files.dart';

/// One recovery snapshot on disk — a row of the Preferences list.
class RecoverySnapshotInfo {
  const RecoverySnapshotInfo({
    required this.path,
    required this.projectName,
    required this.projectPath,
    required this.modified,
    required this.bytes,
  });

  /// The snapshot file itself.
  final String path;

  /// The project's file name, decoded out of the snapshot's name
  /// (`basename.<hash>.autosave`).
  final String projectName;

  /// The full project path when a known project still maps to this
  /// snapshot; null for an orphan — the file name holds only a hash of
  /// the path, so once nothing remembers the path there is no way back.
  final String? projectPath;

  final DateTime modified;
  final int bytes;
}

/// Autosave: a DIRTY session's work is SAVED — into the project file, by
/// the same writer the Save button uses — on the periodic tick. F-1 (유저
/// 2026-08-26) made the clock the ONLY trigger (「심플하게 명시적저장 /
/// n분주기 자동저장만」).
///
/// 🚨★★★**AND THAT IS WHY 「저장 안 하고 닫기 = 버리기」 IS NOW A
/// PROPERTY OF THE SWITCH, NOT OF THE APP.** Three decision comments used
/// to say the project file changes on an explicit save alone, and this
/// service is what made that true by writing a sidecar instead. 유저
/// 2026-09-07 settled it the other way and said the rule had already been
/// settled once: 「기존 결정대로 자동저장이 파일갱신. **그게 싫으면 자동
/// 저장 off하면된다**고 말했는데 안바꿧나보네」.
///
/// So: autosave ON and the file follows the work every n minutes — close
/// without saving and you keep what the last tick wrote. Autosave OFF and
/// the discard rule is literal again. The user owns which, and the switch
/// is where they say so.
///
/// A clock was here once before and was DELETED, for a reason that still
/// governs what this may do: the old tick wrote a whole-archive snapshot
/// and adopted every cel's file ref into it, so the next manual save could
/// no longer see its own work and rewrote the whole thing — incremental
/// save never ran. ⛔This must stay an INCREMENTAL save for the same
/// reason; a tick that rewrote the archive would make a clock unaffordable
/// on documents this size.
///
/// ⚠️The lifecycle triggers that replaced that clock in between (pause,
/// app going background) are gone with F-1 — see the ⛔F-1 decision note
/// in home_page for what an OS kill costs now and why that was accepted.
///
/// PEN-12 #8: a NEVER-SAVED project has nowhere to write — instead of
/// piling files into hidden app-data folders for a document with no
/// identity yet, it fires [onUnsavedProject] so the shell can ask for a
/// real file (OpenToonz-style).
///
/// The service knows nothing about widgets: the shell decides WHEN, this
/// decides WHETHER.
class ProjectAutosaveService {
  ProjectAutosaveService({
    required this.isDirty,
    required this.saveProject,
    required this.projectPath,
    this.needsProjectFile,
    this.onUnsavedProject,
  });

  /// Whether unsaved changes exist (the session's dirty flag).
  final bool Function() isDirty;

  /// Saves the session to [path] — the SAME writer the Save button uses,
  /// without the progress window (nobody is watching a tick).
  final Future<void> Function(String path) saveProject;

  /// The project file's path. Only asked once [needsProjectFile] has said
  /// there is one.
  final String Function() projectPath;

  /// True while the project has never been saved to a real file — a
  /// dirty pass then calls [onUnsavedProject] instead of snapshotting.
  final bool Function()? needsProjectFile;

  /// The shell's "please save first" hook (once-per-session gating is
  /// the shell's business).
  final void Function()? onUnsavedProject;

  bool _writing = false;

  /// One snapshot pass: dirty → write (clean sessions write nothing).
  /// Never throws — a failed snapshot must not disturb editing or block
  /// the lifecycle callback that asked for it.
  ///
  /// Re-entrant calls return immediately rather than queue: a tick can
  /// land while the previous tick's write is still in its isolate (a big
  /// overlay on a slow disk outlives a short interval), and queueing it
  /// would rewrite what the write in flight is about to say.
  Future<void> saveNow() async {
    if (_writing || !isDirty()) {
      return;
    }
    if (needsProjectFile?.call() ?? false) {
      onUnsavedProject?.call();
      return;
    }
    _writing = true;
    try {
      await saveProject(projectPath());
    } on Object catch (_) {
      // Swallowed by design; the next trigger retries.
    } finally {
      _writing = false;
    }
  }

  /// Retires EVERY sidecar that could hold unsaved work for
  /// [projectFilePath] — the sidecar-location setting may have changed
  /// since one was written, so both candidate locations go.
  ///
  /// Called at each of the three moments the unsaved work stops existing:
  /// a successful manual save (it landed in the file), a close WITHOUT
  /// saving (the user threw it away), and a DECLINED recovery (the user
  /// picked the saved file over it). Retiring at all three is what lets a
  /// surviving sidecar mean "this session died without one of them" —
  /// i.e. a crash — which is the entire signal recovery reads. Skip one
  /// and the prompt starts firing over work the user already discarded,
  /// and (for the declined case) keeps firing at every open until the
  /// next manual save.
  ///
  /// SYNC on purpose — but be precise about what that buys. It settles
  /// DELETE-versus-write: nothing can interleave between the existence
  /// check and the unlink. It does NOT settle write-versus-delete, where a
  /// tick that started earlier finishes its own write after the retirement
  /// has already run; that window is an isolate wide and the session's
  /// save-in-flight flag is what closes it.
  ///
  /// Sync also keeps the exit and open flows testable — async `dart:io`
  /// inside `testWidgets` never completes (fake zone) — and matches the
  /// neighbouring reads ([sidecarIsNewer], `newestExistingRecoveryFor`),
  /// which are sync for the same reason. One small file, at save or exit.
  static void retireSidecarsFor(String projectFilePath) {
    for (final candidate in AppSave.recoveryCandidatesFor(projectFilePath)) {
      _deleteSidecar(candidate);
    }
  }

  static void _deleteSidecar(String sidecarPath) {
    try {
      final file = File(sidecarPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on Object catch (_) {
      // A locked sidecar (cloud sync mid-upload) is harmless — recovery
      // compares timestamps.
    }
  }

  /// Every recovery snapshot in the app's Recovery folder, newest first —
  /// the Preferences list (유저 08-26: 「스냅샷 눈으로 볼수있게 설정같은데서
  /// … 위치나 수정날짜같은거 다 있고 거기서 여러개 선택해서 삭제」).
  ///
  /// [knownProjectPaths] (the recent-projects list) is what resolves a
  /// snapshot back to its project's location; a snapshot no path maps to
  /// shows its decoded project NAME only.
  static List<RecoverySnapshotInfo> listRecoverySnapshots({
    required Iterable<String> knownProjectPaths,
  }) {
    final directory = Directory(AppSave.recoveryDirectory());
    if (!directory.existsSync()) {
      return const [];
    }
    final pathBySnapshot = {
      for (final path in knownProjectPaths)
        AppSave.recoveryPathFor(path): path,
    };
    final rows = <RecoverySnapshotInfo>[];
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      // `.tmp-<micros>` temps are a write in flight (or that write's
      // corpse — the sweep takes those), not snapshots to offer.
      if (!path.endsWith('.autosave')) {
        continue;
      }
      final stat = FileStat.statSync(path);
      if (stat.type == FileSystemEntityType.notFound) {
        continue;
      }
      final name = path.split('/').last;
      final trimmed = name.substring(0, name.length - '.autosave'.length);
      final dot = trimmed.lastIndexOf('.');
      rows.add(
        RecoverySnapshotInfo(
          path: path,
          projectName: dot <= 0 ? trimmed : trimmed.substring(0, dot),
          projectPath: pathBySnapshot[path],
          modified: stat.modified,
          bytes: stat.size,
        ),
      );
    }
    rows.sort((a, b) => b.modified.compareTo(a.modified));
    return rows;
  }

  /// Deletes everything in the Recovery folder not modified for
  /// [olderThan] — 유저 결정 08-26 (Q-recovery-gc: 「30일좋고」).
  ///
  /// A snapshot's normal deaths are the three retirement moments of its
  /// OWN project; a project deleted or moved outside the app strands its
  /// snapshot past all three, for ever. Of the surveyed pro tools the
  /// invisible stores either never clean (Word's crash store, CSP's
  /// recovery leftovers — the multi-gigabyte cautionary tale) or wipe on
  /// every clean exit (Photoshop, whose snapshots are self-contained);
  /// the time-based precedents are Word's unsaved drafts (4 days) and
  /// Final Cut (a few days). 30 days is far more conservative than
  /// either, and our snapshot is a DELTA — without its base it could
  /// only ever restore partial work, so an aged orphan protects almost
  /// nothing to begin with.
  ///
  /// Age takes the write temps too: the post-rename sweep only runs on a
  /// later write of the SAME project, which an abandoned project never
  /// gets. Returns how many files went.
  static int sweepAbandonedRecovery({
    Duration olderThan = const Duration(days: 30),
    DateTime? now,
  }) => sweepFilesOlderThan(
    Directory(AppSave.recoveryDirectory()),
    olderThan: olderThan,
    now: now,
  );

  /// Whether [sidecarPath] holds a same-or-newer snapshot than [filePath]
  /// — the open flow's recovery prompt condition. Inclusive on ties: a
  /// surviving sidecar means the manual save never retired it, and
  /// filesystem mtime granularity can collapse close writes.
  static bool sidecarIsNewer({
    required String filePath,
    required String sidecarPath,
  }) {
    // Single stats, not exists-then-mtime: the project file lives in the
    // user's folder, where a sync client can replace it between the two
    // calls — and a throw here escapes the open flow before its try.
    // statSync never throws; vanished reports notFound.
    final sidecarStat = FileStat.statSync(sidecarPath);
    if (sidecarStat.type == FileSystemEntityType.notFound) {
      return false;
    }
    final fileStat = FileStat.statSync(filePath);
    if (fileStat.type == FileSystemEntityType.notFound) {
      return true;
    }
    return !sidecarStat.modified.isBefore(fileStat.modified);
  }
}
