import 'dart:async';
import 'dart:io';

import 'app_save_settings.dart';

/// Autosave (P3): a periodic tick snapshots a DIRTY session into a sidecar
/// `<path>.autosave` next to the saved file. Opening a file with a newer
/// sidecar offers recovery (the menu's open flow).
///
/// A sidecar holds unsaved work, so it dies the moment that work stops
/// existing — see [retireSidecarsFor] for the three moments and why a
/// surviving sidecar has to mean something.
///
/// PEN-12 #8: a NEVER-SAVED project autosaves nowhere — instead of piling
/// sidecars into hidden app-data folders, a dirty tick fires
/// [onUnsavedProject] so the shell can ask the user for a real file
/// (OpenToonz-style).
///
/// The service knows nothing about widgets: the shell starts it
/// (FLUTTER_TEST never runs the timer) and tests drive [tick] directly.
class ProjectAutosaveService {
  ProjectAutosaveService({
    required this.isDirty,
    required this.writeSnapshot,
    required this.autosavePath,
    this.needsProjectFile,
    this.onUnsavedProject,
    this.interval = const Duration(minutes: 5),
  });

  /// Whether unsaved changes exist (the session's dirty flag).
  final bool Function() isDirty;

  /// Writes the current session snapshot to [path] (the session's .anicel
  /// writer pointed at the sidecar — atomic like a manual save).
  final Future<void> Function(String path) writeSnapshot;

  /// The sidecar path for the CURRENT session state (moves when the
  /// project is saved under a new name).
  final String Function() autosavePath;

  /// True while the project has never been saved to a real file — a
  /// dirty tick then calls [onUnsavedProject] instead of snapshotting.
  final bool Function()? needsProjectFile;

  /// The shell's "please save first" hook (once-per-session gating is
  /// the shell's business).
  final void Function()? onUnsavedProject;

  final Duration interval;

  Timer? _timer;
  bool _ticking = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(tick()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// One autosave pass: dirty → snapshot to the sidecar (clean sessions
  /// write nothing). Never throws — a failed autosave must not disturb
  /// editing; the next tick retries.
  Future<void> tick() async {
    if (_ticking || !isDirty()) {
      return;
    }
    if (needsProjectFile?.call() ?? false) {
      onUnsavedProject?.call();
      return;
    }
    _ticking = true;
    try {
      await writeSnapshot(autosavePath());
    } catch (_) {
      // Swallowed by design; the next tick retries.
    } finally {
      _ticking = false;
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
  /// neighbouring reads ([sidecarIsNewer], `newestExistingSidecarFor`),
  /// which are sync for the same reason. One small file, at save or exit.
  static void retireSidecarsFor(String projectFilePath) {
    for (final candidate in AppSave.sidecarCandidatesFor(projectFilePath)) {
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
