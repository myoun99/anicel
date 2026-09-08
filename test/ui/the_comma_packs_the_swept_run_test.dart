import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// THE COMMA SET OVER A BAND (UI-R17 #7).
///
/// The selection branch of the verb: every swept block takes the comma
/// and the run PACKS with the retime ripple (1--2--3-- set to 1 reads
/// 123; TVP), and the selection follows the retimed span so a second
/// press keeps operating on the same cels.
///
/// The other rungs are pinned in `image_layer_session_test.dart` (the
/// band's claim ends the press, and the gate reads its own ladder) and
/// `attached_layer_session_test.dart` (synced rows own no timing); this
/// is the one they leave to the playhead branch.
void main() {
  test('every swept block takes the comma and the run packs behind it — '
      'and the second press lands on the same cels', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final rowA = s.activeLayer!.id;
    for (final frameIndex in [0, 1, 2]) {
      s.selectFrameIndex(frameIndex);
      s.createDrawingAtCurrentFrame();
    }
    expect(_blocks(s), [(0, 1), (1, 2), (2, 3)], reason: 'three cels on ones');

    s.updateFrameRangeSelectionDrag(
      layerId: rowA,
      anchorIndex: 0,
      headIndex: 2,
    );
    s.exposureVerbs.setCommaForSelectionOrCurrent(2);

    expect(
      _blocks(s),
      [(0, 2), (2, 4), (4, 6)],
      reason: 'all three went to twos, and the run repacked behind them',
    );

    // No new sweep: the selection followed the retimed span, so the same
    // three cels answer the next press.
    s.exposureVerbs.setCommaForSelectionOrCurrent(1);

    expect(
      _blocks(s),
      [(0, 1), (1, 2), (2, 3)],
      reason: 'back to ones — the second press found the same three cels',
    );
  });
}

/// The active layer's drawing block spans, for readable expectations.
List<(int, int)> _blocks(EditorSessionManager s) {
  final layer = s.activeLayer!;
  return [
    for (final entry in layer.timeline.entries)
      (entry.key, entry.key + entry.value.length!),
  ];
}
