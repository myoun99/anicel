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

  // ↩️This pinned the opposite until 2026-10-07: 「into the wall … the step
  // changes nothing — not the outline, not the preview, not what the drop
  // will commit」. That left the group a frame RIGHT of where it started
  // with the hand a thousand frames left of it, and the release committed
  // that frame. The wall read as a refused landing only because the planner
  // answers null for 「the run is where it started」 — the conflation R28 #5
  // named for a zero delta (유저: 「더 이상 왼쪽으로 이동이 안먹혀버리고 그
  // 자리에서 멈춰버린다」). A group that can go no further that way than
  // where it started IS where it started.
  //
  // The law this file is for — a step that cannot land holds the one
  // before it — is pinned with a step that truly cannot land, the keys
  // riding a slide: `session/a_slide_of_several_rows_stops_as_one_test.dart`.
  test('a slide into the wall the group started at is HOME, and the drop '
      'commits nothing', () {
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
    expect(s.dragPreview.value, isNotNull);

    // Into the wall: neither run can go in front of frame 0.
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: -1000);
    expect(s.frameRangeSelection.value!.startIndex, 0);
    expect(s.dragPreview.value, isNull);

    s.rangeMove.endFrameRangeMoveDrag();
    expect(layerOf(s, aId).timeline.keys, [0]);
    expect(layerOf(s, bId).timeline.keys, [0]);
  });
}
