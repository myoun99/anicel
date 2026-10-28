import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/frame.dart' show InbetweenMark;

/// A dot belongs to the block that holds the cell it sits on, so the toggle
/// on an empty cell is no edit at all — nothing recorded, no notify.
///
/// ↩️It sat among the whole-block move drag's tests (R10-④b), whose fixture
/// it borrowed, until that drag went (2026-10-24).
void main() {
  test('dot toggle on an empty cell is a session no-op: dots are '
      'block-owned, nothing recorded, no notify', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    final layer = s.activeLayer!;
    expect(layer.timeline.containsKey(0), isTrue, reason: '⛔premise');
    s.selectFrameIndex(4); // Empty space on the row.
    final undoProbe = s.canUndo;
    var notifies = 0;
    s.addListener(() => notifies += 1);

    expect(s.layerMarks.canToggleMarkAtCurrentFrame, isFalse);
    s.layerMarks.toggleMarkAtCurrentFrame(InbetweenMark.two);

    expect(
      s.layers.firstWhere((l) => l.id == layer.id).timeline.containsKey(4),
      isFalse,
    );
    expect(s.canUndo, undoProbe);
    expect(notifies, 0);
  });
}
