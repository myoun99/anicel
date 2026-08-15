import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../timeline/timeline_drag_preview.dart';
import 'editor_drag_session.dart';

/// The movie-end drag (UI-R20 #3): the line edits the movie's FINAL LENGTH
/// — the project's trailing gap past the last cut — never the cuts
/// themselves (the tail gap is as first-class as any other gap on this
/// timeline).
class MovieEndDrag implements EditorDragSession {
  /// Always begins: any grab of the end line is a valid drag, so this is a
  /// plain constructor where a refusable family has a factory.
  MovieEndDrag({
    required int beforeTrailing,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function(int trailingFrames) commitTrailing,
  }) : _before = beforeTrailing,
       _preview = preview,
       _commitTrailing = commitTrailing;

  /// The project's trailing gap when the grip went down.
  final int _before;

  /// The trailing-gap value the drag has arrived at, or null while it shows
  /// "no change". The commit reads THIS, never [_preview].
  int? _after;

  final ValueNotifier<TimelineDragPreview?> _preview;

  /// The session's committer: one `UpdateProjectTrailingFramesCommand`
  /// through history, plus the notify.
  final void Function(int trailingFrames) _commitTrailing;

  /// Applies the cumulative frame delta as a live preview (the movie end
  /// never dips below the content end: the trailing gap clamps at 0).
  @override
  void update(int cumulativeDelta) {
    final next = math.max(0, _before + cumulativeDelta);
    _after = next == _before ? null : next;
    _preview.value = next == _before
        ? null
        : MovieEndDragPreview(trailingFrames: next);
  }

  @override
  void commit() {
    final after = _after;
    _preview.value = null;
    if (after == null) {
      return;
    }
    _commitTrailing(after);
  }

  @override
  void cancel() {
    _preview.value = null;
  }
}
