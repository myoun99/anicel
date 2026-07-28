import 'dart:async';
import 'dart:io';

/// Autosave (P3): a periodic tick snapshots a DIRTY session into a sidecar
/// `<path>.autosave` next to the saved file. A successful MANUAL save
/// deletes the sidecar; opening a file with a newer sidecar offers
/// recovery (the menu's open flow).
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

  /// The app-data folder holding autosaves of never-saved projects.
  /// Deletes [sidecarPath] if present (after a successful manual save).
  static Future<void> deleteSidecar(String sidecarPath) async {
    try {
      final file = File(sidecarPath);
      if (await file.exists()) {
        await file.delete();
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
