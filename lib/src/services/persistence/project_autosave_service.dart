import 'dart:async';
import 'dart:io';

import 'app_save_settings.dart';

/// Autosave (P3): a DIRTY session's work is snapshotted into the app's
/// recovery folder when the app is about to stop being in front of the
/// user. Opening a file with a newer snapshot offers recovery (the menu's
/// open flow).
///
/// It used to be a five-minute TIMER, and the timer is gone. Two reasons,
/// and the second is the one that decided it:
///
/// - It defeated incremental saving outright. Each tick adopted every
///   cel's file ref into the snapshot, so the next manual save could no
///   longer see its own work in the project file and rewrote the whole
///   thing. Incremental save only ever ran when two manual saves landed
///   inside one interval, which in practice is never.
/// - Nobody in the industry runs one on documents this size. Of the
///   professional animation tools surveyed, every desktop one ships its
///   timer OFF by default, and not one writes a complete copy of a
///   multi-gigabyte document on a clock. What they all do instead is
///   shrink the unit of write. The mobile ones, where the OS can kill the
///   process without warning, write on the LIFECYCLE instead — which is
///   the trigger that actually matches when work is at risk.
///
/// A snapshot holds unsaved work, so it dies the moment that work stops
/// existing — see [retireSidecarsFor] for the three moments and why a
/// surviving snapshot has to mean something.
///
/// PEN-12 #8: a NEVER-SAVED project snapshots nowhere — instead of piling
/// files into hidden app-data folders for a document that has no identity
/// yet, it fires [onUnsavedProject] so the shell can ask for a real file
/// (OpenToonz-style).
///
/// The service knows nothing about widgets: the shell decides WHEN, this
/// decides WHETHER.
class ProjectAutosaveService {
  ProjectAutosaveService({
    required this.isDirty,
    required this.writeSnapshot,
    required this.autosavePath,
    this.needsProjectFile,
    this.onUnsavedProject,
  });

  /// Whether unsaved changes exist (the session's dirty flag).
  final bool Function() isDirty;

  /// Writes the current session snapshot to [path] (the session's .anicel
  /// writer pointed at the recovery file — atomic like a manual save).
  final Future<void> Function(String path) writeSnapshot;

  /// The recovery path for the CURRENT session state (moves when the
  /// project is saved under a new name).
  final String Function() autosavePath;

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
  /// Re-entrant calls return immediately rather than queue: the triggers
  /// arrive in bursts (inactive, then hidden, then paused, for one trip to
  /// the home screen) and each would otherwise rewrite what the last one
  /// just wrote.
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
      await writeSnapshot(autosavePath());
    } catch (_) {
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
    } catch (_) {
      // A locked sidecar (cloud sync mid-upload) is harmless — recovery
      // compares timestamps.
    }
  }

  /// Whether [sidecarPath] holds a same-or-newer snapshot than [filePath]
  /// — the open flow's recovery prompt condition. Inclusive on ties: a
  /// surviving sidecar means the manual save never retired it, and
  /// filesystem mtime granularity can collapse close writes.
  static bool sidecarIsNewer({
    required String filePath,
    required String sidecarPath,
  }) {
    final file = File(filePath);
    final sidecar = File(sidecarPath);
    if (!sidecar.existsSync()) {
      return false;
    }
    if (!file.existsSync()) {
      return true;
    }
    return !sidecar.lastModifiedSync().isBefore(file.lastModifiedSync());
  }
}
