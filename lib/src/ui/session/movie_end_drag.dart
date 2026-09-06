import 'drags/movie_end_drag.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../services/commands/update_project_trailing_frames_command.dart';
import 'session_roles.dart';

/// The MOVIE-END DRAG — the grip on the movie's last frame — as its own object:
/// where the movie's content actually ends, and the steps of dragging the end
/// past or before it.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: the family owned one field and
/// touched three session members. It names the roles it needs in its constructor.
class MovieEndDragVerbs {
  MovieEndDragVerbs({
    required ProjectAccess project,
    required ChangeSink changes,
    required SessionInternals internals,
  }) : _project = project,
       _changes = changes,
       _internals = internals;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final SessionInternals _internals;

  /// The in-flight end-line drag ([MovieEndDrag]), or null.
  MovieEndDrag? _movieEndDrag;

  /// The movie's content end: the last cut end across every track.
  int get movieContentEndFrame {
    var end = 0;
    for (final entry in buildStoryboardTimelineLayout(
      _project.repository.requireProject(),
    )) {
      if (entry.endFrame > end) {
        end = entry.endFrame;
      }
    }
    return end;
  }

  /// Starts an end-line drag (UI-R20 #3): the line edits the movie's
  /// FINAL LENGTH — the project's trailing gap past the last cut — never
  /// the cuts themselves (the tail gap is as first-class as any other
  /// gap on this timeline).
  bool beginMovieEndDrag() {
    _movieEndDrag = MovieEndDrag(
      beforeTrailing: _project.repository.requireProject().trailingFrames,
      preview: _internals.dragPreview,
      commitTrailing: (trailingFrames) {
        _project.historyManager.execute(
          UpdateProjectTrailingFramesCommand(
            repository: _project.repository,
            trailingFrames: trailingFrames,
          ),
        );
        _changes.notifyChanged();
      },
    );
    return true;
  }

  void updateMovieEndDrag(int cumulativeDelta) =>
      _movieEndDrag?.update(cumulativeDelta);

  void endMovieEndDrag() {
    _movieEndDrag?.commit();
    _movieEndDrag = null;
  }

  void cancelMovieEndDrag() {
    _movieEndDrag?.cancel();
    _movieEndDrag = null;
  }
}
