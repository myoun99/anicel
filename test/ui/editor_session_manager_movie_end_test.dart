import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// UI-R20 #3: the movie-end drag edits the PROJECT's trailing gap — the
/// final length lives past the last cut, never inside it.
void main() {
  test('the end drag grows/shrinks the trailing gap with a live preview '
      'and ONE undo; the movie end never dips below the content end', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final contentEnd = s.movieContentEndFrame;
    expect(s.repository.requireProject().trailingFrames, 0);

    expect(s.beginMovieEndDrag(), isTrue);
    s.updateMovieEndDrag(6);
    // The preview rides the channel; the repository stays untouched.
    expect(
      (s.dragPreview.value as MovieEndDragPreview).trailingFrames,
      6,
    );
    expect(s.repository.requireProject().trailingFrames, 0);

    // Below the content end clamps at 0 trailing.
    s.updateMovieEndDrag(-40);
    expect(s.dragPreview.value, isNull, reason: 'clamped back to no change');

    s.updateMovieEndDrag(10);
    s.endMovieEndDrag();
    expect(s.repository.requireProject().trailingFrames, 10);
    expect(s.movieContentEndFrame, contentEnd, reason: 'cuts untouched');
    expect(s.dragPreview.value, isNull);

    // ONE undo step.
    s.undo();
    expect(s.repository.requireProject().trailingFrames, 0);
    s.redo();
    expect(s.repository.requireProject().trailingFrames, 10);
  });

  test('the trailing gap round-trips through json', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.beginMovieEndDrag();
    s.updateMovieEndDrag(7);
    s.endMovieEndDrag();

    final json = s.repository.requireProject().toJson();
    expect(json['trailingFrames'], 7);
  });

  test('the commit survives the display channel being cleared', () {
    // [dragPreview] is DISPLAY, shared by every drag family; a consumer may
    // clear it mid-flight. The commit reads the family's own stored
    // after-state — this dies if endMovieEndDrag goes back to the channel.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    s.beginMovieEndDrag();
    s.updateMovieEndDrag(10);
    s.dragPreview.value = null; // A consumer dropped the preview.
    s.endMovieEndDrag();

    expect(s.repository.requireProject().trailingFrames, 10);
  });

  test('cancel leaves no trace', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final undoProbe = s.canUndo;

    s.beginMovieEndDrag();
    s.updateMovieEndDrag(5);
    s.cancelMovieEndDrag();

    expect(s.dragPreview.value, isNull);
    expect(s.repository.requireProject().trailingFrames, 0);
    expect(s.canUndo, undoProbe);
  });
}
