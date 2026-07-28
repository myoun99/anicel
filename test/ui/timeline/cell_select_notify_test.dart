import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Selecting a cell in the row you are ALREADY on must not announce.
///
/// A timeline cell tap sends the layer and then the frame. The seek half is
/// deliberately notify-free — it rides the cursor notifier so the playhead
/// moves without a rebuild — but `selectLayer` announced unconditionally, so
/// every click after the first in a row still rebuilt the whole panel. That
/// is the "selection lags the pointer" report.
void main() {
  late EditorSessionManager session;
  var notifies = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    session.addListener(() => notifies += 1);
    notifies = 0;
  });

  tearDown(() => session.dispose());

  test('re-selecting the active layer announces nothing', () {
    final first = session.layers.first.id;
    session.selectLayer(first);
    notifies = 0;

    session.selectLayer(first);
    session.selectLayer(first);

    expect(notifies, 0);
    expect(session.activeLayerId, first);
  });

  test('selecting a DIFFERENT layer still announces', () {
    final ids = session.layers.map((layer) => layer.id).toList();
    expect(ids.length, greaterThan(1), reason: 'need two layers to switch');
    session.selectLayer(ids.first);
    notifies = 0;

    session.selectLayer(ids[1]);

    expect(notifies, 1);
    expect(session.activeLayerId, ids[1]);
  });

  test('a frame-range selection on another row still drops — and announces '
      'even when the layer itself does not move', () {
    final ids = session.layers.map((layer) => layer.id).toList();
    session.selectLayer(ids.first);
    session.selectFrameIndex(0);
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: ids[1],
      startIndex: 0,
      endIndexExclusive: 2,
    );
    notifies = 0;

    // Same active layer, but the live selection belongs to another row: the
    // drop is a real state change and has to be announced.
    session.selectLayer(ids.first);

    expect(session.frameRangeSelection.value, isNull);
    expect(notifies, 1);
  });
}
