import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/ruler_marker.dart';
import 'package:anicel/src/ui/session/drags/ruler_marker_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ruler marker's drag (I-169) signs up for the drag session's laws
/// (`a_drag_session_signs_up_for_four_laws_test`): what it shows mid-drag is
/// a preview and no step; a commit lands ONE step from its own after-state;
/// a drag back to where it started is no step; a cancel touches nothing.
void main() {
  const holder = RulerMarkerHolder.cut(CutId('cut'));
  final before = RulerMarkers.settled(const [
    RulerMarker(start: 2, length: 2, text: 'a'),
    RulerMarker(start: 8, text: 'b'),
  ]);

  ({
    RulerMarkerDrag drag,
    ValueNotifier<TimelineDragPreview?> preview,
    List<RulerMarkers> committed,
  })
  open({int index = 0}) {
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    final committed = <RulerMarkers>[];
    return (
      drag: RulerMarkerDrag(
        holder: holder,
        before: before,
        index: index,
        preview: preview,
        commit: committed.add,
      ),
      preview: preview,
      committed: committed,
    );
  }

  test('a step shows the ruler\'s markers as the blocks\' plan leaves them, '
      'on that ruler alone', () {
    final session = open();

    session.drag.update(3);

    expect(
      session.preview.value,
      RulerMarkerDragPreview(holder: holder, markers: before.moved(0, 3)),
    );
    expect(session.committed, isEmpty, reason: 'nothing lands mid-drag');
    expect(
      rulerMarkersUnder(session.preview.value, holder, before),
      before.moved(0, 3),
    );
    expect(
      rulerMarkersUnder(
        session.preview.value,
        const RulerMarkerHolder.timeline(),
        const RulerMarkers.none(),
      ),
      const RulerMarkers.none(),
      reason: 'the timeline\'s ruler shows its own (I-169-Q2)',
    );
    expect(rulerMarkersUnder(null, holder, before), before);
  });

  test('every step is planned from where the hand went down', () {
    final session = open();

    session.drag.update(3);
    session.drag.update(1);
    session.drag.commit();

    expect(session.committed, [before.moved(0, 1)]);
    expect(session.preview.value, isNull, reason: 'the closer clears it');
  });

  test('🚨a drag that ends back where it started commits nothing', () {
    final session = open();

    session.drag.update(3);
    session.drag.update(0);
    expect(session.preview.value, isNull);
    session.drag.commit();

    expect(session.committed, isEmpty);
  });

  test('a marker stops against its neighbour, and at the ruler\'s first '
      'frame', () {
    final session = open(index: 1);

    session.drag.update(-4);
    session.drag.commit();
    expect(session.committed, [before.moved(1, -4)]);
    expect(session.committed.single.inOrder.last.start, 4);

    final held = open();
    held.drag.update(-2);
    held.drag.update(-50);
    held.drag.commit();
    expect(held.committed.single.inOrder.first.start, 0);
  });

  test('cancel drops the preview and touches no history', () {
    final session = open();

    session.drag.update(3);
    session.drag.cancel();

    expect(session.committed, isEmpty);
    expect(session.preview.value, isNull);
  });

  test('a project view is handed the project itself under a marker drag', () {
    // No view shows a marker but its ruler's own layer, so nothing built
    // from the project is built again for a step.
    final preview = RulerMarkerDragPreview(holder: holder, markers: before);
    final project = createDefaultProject();
    expect(
      projectWithTimelineDragPreview(project, preview),
      same(project),
    );
    expect(preview, RulerMarkerDragPreview(holder: holder, markers: before));
    expect(
      preview.hashCode,
      RulerMarkerDragPreview(holder: holder, markers: before).hashCode,
    );
    expect(
      preview,
      isNot(
        RulerMarkerDragPreview(
          holder: const RulerMarkerHolder.timeline(),
          markers: before,
        ),
      ),
    );
  });
}
