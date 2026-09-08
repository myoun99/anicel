import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/session/block_shift.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// THE PULL STOPS WHERE THE FIRST ROW RUNS OUT OF ROOM.
///
/// Design D's slack rule over a band that names MORE THAN ONE row: the
/// scope's rows travel together, so the whole shove is clamped to the
/// LEAST slack among them — a roomier row never drags a tighter one past
/// its wall. The other rungs of the shove (the axis carry, the SE
/// translation, the aiming) are pinned in `push_pull_test.dart`,
/// `storyboard_selection_verbs_test.dart` and `timeline_se_global_test.dart`;
/// this is the one they leave to a single row.
void main() {
  test('the pull is clamped to the tightest row in the band, and every row '
      'travels that far', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    // Row A: blocks at 0 and 4 — three empty frames in front of the second.
    final rowA = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame();

    // Row B: blocks at 0 and 8 — seven empty frames, more room than A.
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final rowB = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(8);
    s.createDrawingAtCurrentFrame();

    // A band across BOTH rows, anchored at 4.
    s.updateFrameRangeSelectionDrag(
      layerId: rowA,
      anchorIndex: 4,
      headIndex: 4,
      headLayerId: rowB,
    );

    // 🚨Held through its OWN type, not through the session: a mutation run
    // aims at a collaborator only via the tests that import it, and
    // `lib/src/ui/session/` was 63 files of UNNAMED because every pin
    // reached the verb through `EditorSessionManager` (round 8 #6).
    final shove = shoveOf(s);

    expect(
      shove.framePullSlack(),
      3,
      reason:
          'row A has three frames of room and row B seven — the scope '
          'stops at three',
    );

    shove.pullFrames(9);

    expect(_blocks(s, rowA), [(0, 1), (1, 2)], reason: 'A closed its gap');
    expect(
      _blocks(s, rowB),
      [(0, 1), (5, 6)],
      reason: 'B travelled the SAME three frames, not its own seven',
    );
    expect(shove.canPullFrames(), isFalse, reason: 'A is packed now');
  });
}

List<(int, int)> _blocks(EditorSessionManager s, LayerId layerId) {
  final layer = s.layers.firstWhere((layer) => layer.id == layerId);
  return [
    for (final entry in layer.timeline.entries)
      (entry.key, entry.key + entry.value.length!),
  ];
}

/// The frame-axis shove under its OWN name.
///
/// 🚨`tool/mutation_run.dart` picks the tests that will witness a mutation by
/// asking which tests IMPORT the file, and every pin of this law arrived
/// through [EditorSessionManager] — so 63 of the 71 files under
/// `lib/src/ui/session/` reported UNNAMED (round 8 #6).
BlockShift shoveOf(EditorSessionManager session) => session.blockShift;
