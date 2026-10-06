// A RANGE-MOVE STEP THAT CANNOT LAND HOLDS THE LAST VALID ONE.
//
// Two survivors of the mutation campaign (2026-09-03, the rigid row hop
// cut): the pointer leaving the rows fell through to the plain slide
// (`holds: false`), and an illegal slide step went on to publish an empty
// preview (`illegal` no longer gating the riders). Each pin drives the
// session's drag and reads the drop.
//
// ↩️A third stood here until F-276 (유저 2026-10-04): "a SYNCED attach row
// carrying content keeps the span on the frame axis — the rigid hop stands
// down". It pinned code, not a decision, and the user asked for the
// opposite: 「프레임 블록은 이동가능한곳이라면 어디든 이동가능」. A row that
// cannot hop no longer keeps the rows that can — pinned in
// `session/a_block_leaves_a_row_that_carries_attach_rows_test.dart`.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  Layer layerOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((l) => l.id == id);

  /// A (block at 0), B (block at 0), C empty — top to bottom.
  (EditorSessionManager, LayerId a, LayerId b, LayerId c) threeRows() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    final aId = s.activeLayer!.id;
    s.layerStack.addLayer();
    final bId = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.layerStack.addLayer();
    final cId = s.activeLayer!.id;
    return (s, aId, bId, cId);
  }

  test('the pointer leaving the rows HOLDS the last valid rigid landing', () {
    final (s, aId, bId, cId) = threeRows();
    final aFrameId = layerOf(s, aId).frames.single.id;
    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(
      layerId: aId,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: bId,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(s.frameRangeSelection.value!.spanLayerIds, [bId, cId]);

    // Off the rows entirely: nothing to hop to, so the step neither hops
    // nor falls back to the slide — the landing it had is the one it keeps.
    s.rangeMove.updateFrameRangeMoveDrag(
      frameDelta: 0,
      targetLayerId: const LayerId('no-such-row'),
    );
    expect(s.frameRangeSelection.value!.spanLayerIds, [bId, cId]);
    expect(s.dragPreview.value, isNotNull);

    s.rangeMove.endFrameRangeMoveDrag();
    expect(layerOf(s, aId).timeline.keys, isEmpty);
    expect(layerOf(s, bId).timeline[0]!.frameId, aFrameId);
  });

  test('an ILLEGAL slide step HOLDS the last valid slide, and the drop '
      'commits that one', () {
    final (s, aId, bId, _) = threeRows();
    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(
      layerId: aId,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: bId,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);
    expect(s.frameRangeSelection.value!.startIndex, 1);
    final held = s.dragPreview.value;
    expect(held, isNotNull);

    // Into the wall: the run clamps to frame 0, where it already was, so no
    // plan lands and the step changes nothing — not the outline, not the
    // preview, not what the drop will commit.
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: -1000);
    expect(s.frameRangeSelection.value!.startIndex, 1);
    expect(s.dragPreview.value, same(held));

    s.rangeMove.endFrameRangeMoveDrag();
    expect(layerOf(s, aId).timeline.containsKey(1), isTrue);
    expect(layerOf(s, bId).timeline.containsKey(1), isTrue);
  });
}
