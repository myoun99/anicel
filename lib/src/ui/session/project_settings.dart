part of '../editor_session_manager.dart';

/// The PROJECT SETTINGS — the project's frame rate, backdrop, background,
/// pasteboard, and the storyboard timeline layout memo — as their own
/// object. The audio, media and file settings stay where they are: they
/// belong to another lane.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: two memo fields of its own, and
/// the rest reads it in four places (the track axis and the flip asking
/// for the layout).
class _ProjectSettings {
  _ProjectSettings(this._session);

  final EditorSessionManager _session;

  /// One undo step; no-op when unchanged. Writes the PROJECT's pasteboard
  /// (R3b promotion) — and remembers the choice as the app-level default
  /// for the NEXT project, which is all that remains of the old app-state
  /// pasteboard.
  void setPasteboardColor(int argb) {
    _session._cutCommandCoordinator.setProjectPasteboard(argb);
    _session._notifyChanged();
    _session._appSettings.rememberPasteboardDefault(argb);
  }

  /// One undo step; no-op when unchanged. The BACKDROP (R3b): the stage's
  /// opaque floor — what a fade reveals and what an opaque export bakes
  /// where nothing covers.
  void setProjectBackdrop(int argb) {
    _session._cutCommandCoordinator.setProjectBackdrop(argb);
    _session._notifyChanged();
  }

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights — where the pasteboard stops and the backdrop begins. One undo
  /// step; no-op when unchanged.
  void setProjectPasteboardMargin(double margin) {
    _session._cutCommandCoordinator.setProjectPasteboardMargin(margin);
    _session._notifyChanged();
  }

  /// The exact rate, for the surfaces that convert frames to REAL TIME
  /// (playback clock, audio placement, export). Everything that merely
  /// COUNTS frames wants [projectFps] instead.
  ProjectFrameRate get projectFrameRate =>
      _session._repository.requireProject().frameRate;

  int get projectFps => _session._repository.requireProject().fps;

  void setProjectFrameRate(ProjectFrameRate frameRate) {
    if (frameRate.numerator < 1 ||
        frameRate.denominator < 1 ||
        frameRate.countingBase < 1 ||
        frameRate == projectFrameRate) {
      return;
    }
    _session._historyManager.execute(
      UpdateProjectFrameRateCommand(
        repository: _session._repository,
        frameRate: frameRate,
      ),
    );
    _session._warmActiveCut();
    _session._notifyChanged();
  }

  /// Whole-number convenience for the callers that only ever mean an
  /// integer rate (the custom-rate dialog, tests).
  void setProjectFps(int fps) {
    if (fps < 1) {
      return;
    }
    setProjectFrameRate(ProjectFrameRate.integer(fps));
  }

  /// The project's paper/background (R10-⑥): canvas paper, playback gap
  /// fill and export backing.
  ProjectBackground get projectBackground =>
      _session._repository.requireProject().background;

  /// One undo step; no-op when unchanged. Composites are untouched — the
  /// background paints at display/export time, never baked (the camera
  /// rule).
  void setProjectBackground(ProjectBackground background) {
    _session._cutCommandCoordinator.setProjectBackground(background);
    _session._notifyChanged();
  }

  /// The whole-project layout, memoized on PROJECT IDENTITY: scrubs ask
  /// per MOVE and all-cuts playback per TICK, and the project only changes
  /// identity on an edit — rebuilding the whole cross-track layout each
  /// call was a fixed per-move tax (the same memo the storyboard host
  /// keeps).
  /// The memoized layout, for surfaces outside this class that need the
  /// same cut ranges — the flip HUD's gap window reads the track's cuts
  /// through here rather than rebuilding a second layout that could
  /// disagree with the one the flip walks.
  List<StoryboardTimelineLayoutEntry> projectTimelineLayout() =>
      projectLayout();

  List<StoryboardTimelineLayoutEntry> projectLayout() {
    final project = _session.repository.requireProject();
    if (!identical(project, _projectLayoutProject)) {
      _projectLayoutProject = project;
      _projectLayoutMemo = buildStoryboardTimelineLayout(project);
    }
    return _projectLayoutMemo!;
  }

  Project? _projectLayoutProject;

  List<StoryboardTimelineLayoutEntry>? _projectLayoutMemo;
}
