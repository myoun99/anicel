part of '../editor_session_manager.dart';

/// The MOVIE-END DRAG — the grip on the movie's last frame — as its own object:
/// where the movie's content actually ends, and the steps of dragging the end
/// past or before it.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: the family owned one field and
/// touched three session members. It reaches the session through `_session`.
class _MovieEndDrag {
  _MovieEndDrag(this._session);

  final EditorSessionManager _session;

  /// The in-flight end-line drag ([MovieEndDrag]), or null.
  MovieEndDrag? _movieEndDrag;

  /// The movie's content end: the last cut end across every track.
  int get movieContentEndFrame {
    var end = 0;
    for (final entry in buildStoryboardTimelineLayout(
      _session.repository.requireProject(),
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
      beforeTrailing: _session.repository.requireProject().trailingFrames,
      preview: _session.dragPreview,
      commitTrailing: (trailingFrames) {
        _session.historyManager.execute(
          UpdateProjectTrailingFramesCommand(
            repository: _session.repository,
            trailingFrames: trailingFrames,
          ),
        );
        _session.notifyChanged();
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
