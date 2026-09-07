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
/// 🪦**AND THE SIDECAR MACHINERY IS GONE WITH IT** (2026-09-08): the
/// overlay writer, the Recovery folder and its list, the 30-day sweep, the
/// recovery prompt on open, and the retirement that fired at each of the
/// three moments unsaved work stopped existing. All of it existed to hold
/// work the project file was not allowed to hold; the file holds it now.
/// The reader outlived the writer by one round on purpose — a crash on a
/// build older than that decision left a sidecar on somebody's disk, and
/// deleting reader and writer together would have dropped it without a
/// word.
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
  /// dirty pass then calls [onUnsavedProject] instead of saving.
  final bool Function()? needsProjectFile;

  /// The shell's "please save first" hook (once-per-session gating is
  /// the shell's business).
  final void Function()? onUnsavedProject;

  bool _writing = false;

  /// One pass: dirty → save (clean sessions write nothing). Never throws —
  /// a failed tick must not disturb editing or block the lifecycle
  /// callback that asked for it.
  ///
  /// Re-entrant calls return immediately rather than queue: a tick can
  /// land while the previous tick's write is still in its isolate (a big
  /// save on a slow disk outlives a short interval), and queueing it
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
}
