// A RANGE-MOVE STEP THAT CANNOT LAND HOLDS THE LAST VALID ONE, AND A ROW
// THAT CANNOT HOP KEEPS THE WHOLE SPAN ON THE FRAME AXIS.
//
// Three survivors of the mutation campaign (2026-09-03, the rigid row hop
// cut): the pointer leaving the rows fell through to the plain slide
// (`holds: false`), an illegal slide step went on to publish an empty
// preview (`illegal` no longer gating the riders), and a SYNCED attach row
// carrying content no longer vetoed the rigid hop. Each pin drives the
// session's drag and reads the drop.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
    s.addLayer();
    final bId = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.addLayer();
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
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(s.frameRangeSelection.value!.spanLayerIds, [bId, cId]);

    // Off the rows entirely: nothing to hop to, so the step neither hops
    // nor falls back to the slide — the landing it had is the one it keeps.
    s.updateFrameRangeMoveDrag(
      frameDelta: 0,
      targetLayerId: const LayerId('no-such-row'),
    );
    expect(s.frameRangeSelection.value!.spanLayerIds, [bId, cId]);
    expect(s.dragPreview.value, isNotNull);

    s.endFrameRangeMoveDrag();
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
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 1);
    expect(s.frameRangeSelection.value!.startIndex, 1);
    final held = s.dragPreview.value;
    expect(held, isNotNull);

    // Into the wall: the run clamps to frame 0, where it already was, so no
    // plan lands and the step changes nothing — not the outline, not the
    // preview, not what the drop will commit.
    s.updateFrameRangeMoveDrag(frameDelta: -1000);
    expect(s.frameRangeSelection.value!.startIndex, 1);
    expect(s.dragPreview.value, same(held));

    s.endFrameRangeMoveDrag();
    expect(layerOf(s, aId).timeline.containsKey(1), isTrue);
    expect(layerOf(s, bId).timeline.containsKey(1), isTrue);
  });

  test('a SYNCED attach row carrying content keeps the span on the frame '
      'axis: the rigid hop stands down instead of hopping the drawing row '
      'alone', () {
    final (s, aId, bId, cId) = threeRows();
    s.selectLayer(aId);
    s.addAttachedLayer(AttachedPlacement.below);
    final syncedId = s.activeLayer!.id;
    final bFrameId = layerOf(s, bId).frames.single.id;
    expect(
      layerOf(s, syncedId).timeline.containsKey(0),
      isTrue,
      reason: 'the synced row mirrors the base block inside the range',
    );

    s.selectLayer(bId);
    s.updateFrameRangeSelectionDrag(
      layerId: bId,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: syncedId,
    );
    expect(
      s.frameRangeSelection.value!.spanLayerIds,
      containsAll([syncedId, bId]),
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: cId);
    s.endFrameRangeMoveDrag();

    // B stayed home: the synced row's timing belongs to its base, so the
    // span could only slide — and a zero slide is no move at all.
    expect(layerOf(s, bId).timeline[0]!.frameId, bFrameId);
    expect(layerOf(s, cId).timeline.keys, isEmpty);
  });
}
