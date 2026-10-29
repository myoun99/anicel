import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/session/drags/movie_end_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// 🚨THE DRAG SESSION'S FOUR LAWS, ON THE MOVIE END, WHICH NOTHING NAMED.
///
/// A session is begun by CONSTRUCTING it, driven by `update`, and closed by
/// exactly one of `commit` or `cancel`. What each subtype signs up for:
///
/// * a begin that must refuse is a factory returning null — no object, no
///   drag;
/// * `commit` lands AT MOST ONE undo step, built from the object's OWN
///   after-state, never read back out of the preview channel (the
///   invariant movie-end violated until 2026-08-16);
/// * `cancel` drops the preview and touches no history;
/// * both closers leave the preview channel null.
void main() {
  group('MovieEndDrag — the line edits the movie length, never the cuts', () {
    ({
      MovieEndDrag drag,
      ValueNotifier<TimelineDragPreview?> preview,
      List<int> committed,
    })
    open({int before = 10}) {
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(preview.dispose);
      final committed = <int>[];
      return (
        drag: MovieEndDrag(
          beforeTrailing: before,
          preview: preview,
          commitTrailing: committed.add,
        ),
        preview: preview,
        committed: committed,
      );
    }

    test('a drag out previews the new trailing gap', () {
      final session = open();

      session.drag.update(5);

      final preview = session.preview.value;
      expect(preview, isA<MovieEndDragPreview>());
      expect((preview! as MovieEndDragPreview).trailingFrames, 15);
      expect(session.committed, isEmpty, reason: 'nothing lands mid-drag');
    });

    test('⛔the movie end never dips below the content end — the trailing '
        'gap clamps at 0', () {
      final session = open();

      session.drag.update(-999);
      session.drag.commit();

      expect(session.committed, [0]);
    });

    test('commit lands ONE step, from the drag\'s own after-state', () {
      final session = open();

      session.drag.update(5);
      session.drag.commit();

      expect(session.committed, [15]);
      expect(session.preview.value, isNull, reason: 'the closer clears it');
    });

    test('🚨a drag that ends back where it STARTED commits nothing — "no '
        'change" is not an undo step', () {
      final session = open();

      session.drag.update(5);
      session.drag.update(0);
      session.drag.commit();

      expect(session.committed, isEmpty);
      expect(session.preview.value, isNull);
    });

    test('cancel drops the preview and touches no history', () {
      final session = open();

      session.drag.update(5);
      session.drag.cancel();

      expect(session.committed, isEmpty);
      expect(session.preview.value, isNull);
    });
  });
}
