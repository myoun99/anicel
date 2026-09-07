import '../../models/project_background.dart';
import '../../models/project_frame_rate.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../services/command.dart';
import '../../services/commands/update_project_frame_rate_command.dart';
import 'session_roles.dart';
import '../../core/identity_memo.dart';

/// The PROJECT SETTINGS — the project's frame rate, backdrop, background,
/// pasteboard, and the storyboard timeline layout memo — as their own
/// object. The media and file settings stay where they are: they belong
/// to another lane. The AUDIO settings landed in [ProjectAudio] (G3), and
/// they share this class's [commitProjectSetting].
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: two memo fields of its own, and
/// the rest reads it in four places (the track axis and the flip asking
/// for the layout).
class ProjectSettings {
  ProjectSettings({
    required ProjectAccess project,
    required ChangeSink changes,
    required SessionInternals internals,
  }) : _project = project,
       _changes = changes,
       _internals = internals;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final SessionInternals _internals;

  /// One undo step; no-op when unchanged. Writes the PROJECT's pasteboard
  /// (R3b promotion) — and remembers the choice as the app-level default
  /// for the NEXT project, which is all that remains of the old app-state
  /// pasteboard.
  void setPasteboardColor(int argb) {
    _project.cutCommandCoordinator.setProjectPasteboard(argb);
    _changes.notifyChanged();
    _internals.appSettings.rememberPasteboardDefault(argb);
  }

  /// One undo step; no-op when unchanged. The BACKDROP (R3b): the stage's
  /// opaque floor — what a fade reveals and what an opaque export bakes
  /// where nothing covers.
  void setProjectBackdrop(int argb) {
    _project.cutCommandCoordinator.setProjectBackdrop(argb);
    _changes.notifyChanged();
  }

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights — where the pasteboard stops and the backdrop begins. One undo
  /// step; no-op when unchanged.
  void setProjectPasteboardMargin(double margin) {
    _project.cutCommandCoordinator.setProjectPasteboardMargin(margin);
    _changes.notifyChanged();
  }

  /// The exact rate, for the surfaces that convert frames to REAL TIME
  /// (playback clock, audio placement, export). Everything that merely
  /// COUNTS frames wants [projectFps] instead.
  ProjectFrameRate get projectFrameRate =>
      _project.repository.requireProject().frameRate;

  int get projectFps => _project.repository.requireProject().fps;

  void setProjectFrameRate(ProjectFrameRate frameRate) {
    if (frameRate.numerator < 1 ||
        frameRate.denominator < 1 ||
        frameRate.countingBase < 1 ||
        frameRate == projectFrameRate) {
      return;
    }
    commitProjectSetting(
      UpdateProjectFrameRateCommand(
        repository: _project.repository,
        frameRate: frameRate,
      ),
      _changes.warmActiveCut,
    );
  }

  /// ⛔THE ONE WAY A PROJECT-WIDE SETTING LANDS (G3, 2026-09-07): the
  /// command goes through history, then whatever this particular setting
  /// made stale is re-warmed, then the session notifies ONCE. Three
  /// setters had spelled this out — the frame rate, the frame rate with an
  /// audio pull, and the audio sample rate — and a second spelling is how
  /// one of them comes to notify while another does not.
  ///
  /// [invalidates] is the only difference between them, and it is a
  /// STRATEGY, not a flag: the frame rate re-warms the active cut, the
  /// audio settings re-warm the conforms, and the pull does both.
  void commitProjectSetting(Command command, void Function() invalidates) {
    _project.historyManager.execute(command);
    invalidates();
    _changes.notifyChanged();
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
      _project.repository.requireProject().background;

  /// One undo step; no-op when unchanged. Composites are untouched — the
  /// background paints at display/export time, never baked (the camera
  /// rule).
  void setProjectBackground(ProjectBackground background) {
    _project.cutCommandCoordinator.setProjectBackground(background);
    _changes.notifyChanged();
  }

  /// The whole-project layout, memoized on PROJECT IDENTITY: scrubs ask
  /// per MOVE and all-cuts playback per TICK, and the project only changes
  /// identity on an edit — rebuilding the whole cross-track layout each
  /// call was a fixed per-move tax (the same memo the storyboard host
  /// keeps).
  ///
  /// Also the memoized layout for surfaces outside this class that need
  /// the same cut ranges — the flip HUD's gap window reads the track's
  /// cuts through here rather than rebuilding a second layout that could
  /// disagree with the one the flip walks.
  List<StoryboardTimelineLayoutEntry> projectLayout() {
    final project = _project.repository.requireProject();
    return _layout.resolve(
      identity: project,
      build: () => buildStoryboardTimelineLayout(project),
    );
  }

  final _layout = IdentityMemo<List<StoryboardTimelineLayoutEntry>>();
}
