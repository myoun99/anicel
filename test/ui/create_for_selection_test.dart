import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// UI-R25 #3: Add with a live selection fills the WHOLE selection — every
/// selectable row kind creates over its selected range.
void main() {
  EditorSessionManager session() =>
      EditorSessionManager(initialProject: createDefaultProject());

  Layer layerOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((l) => l.id == id);

  test('no selection = not owned (the plain playhead flow runs)', () {
    final s = session();
    expect(s.createInstancesForSelection(), isFalse);
  });

  test('a drawing-row span fills every EMPTY gap with a gap-length cel in '
      'ONE undo; covered cells stay untouched', () {
    final s = session();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame(); // covered island at 2
    final aId = s.activeLayer!.id;
    s.addLayer();
    final bId = s.activeLayer!.id; // empty second row

    s.updateFrameRangeSelectionDrag(
      layerId: aId,
      anchorIndex: 0,
      headIndex: 5,
      headLayerId: bId,
    );
    expect(s.createInstancesForSelection(), isTrue);

    final a = layerOf(s, aId);
    // Gaps [0,2) and [3,6) filled around the untouched island at 2.
    expect(a.timeline[0]!.length, 2);
    expect(a.timeline[3]!.length, 3);
    expect(a.frames, hasLength(3));
    final b = layerOf(s, bId);
    expect(b.timeline[0]!.length, 6, reason: 'empty row fills the range');

    // ONE undo restores both rows.
    s.undo();
    expect(layerOf(s, aId).timeline.keys.toList(), [2]);
    expect(layerOf(s, bId).timeline.keys, isEmpty);
  });

  test('an SE row fills its selected gap with one entry; an instruction '
      'row gains a default-vocabulary event over the gap', () {
    final s = session();
    s.addLayerOfKind(LayerKind.se);
    final seId = s.activeLayer!.id;
    s.updateFrameRangeSelectionDrag(
      layerId: seId,
      anchorIndex: 1,
      headIndex: 4,
    );
    expect(s.createInstancesForSelection(), isTrue);
    final se = layerOf(s, seId);
    expect(se.timeline[1]!.length, 4);

    s.addLayerOfKind(LayerKind.instruction);
    final instrId = s.activeLayer!.id;
    s.updateFrameRangeSelectionDrag(
      layerId: instrId,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(s.createInstancesForSelection(), isTrue);
    final instr = layerOf(s, instrId);
    expect(instr.instructions[0]!.length, 3);
    expect(
      instr.instructions[0]!.instructionId,
      s.cameraInstructionSet.defs.first.id,
    );
  });

  test('a camera-row span freezes a pose key on every unkeyed frame in '
      'ONE undo', () {
    final s = session();
    final cameraId = s.layers
        .firstWhere((l) => l.kind == LayerKind.camera)
        .id;
    s.setCameraKeyframeAtCurrentFrame(s.cameraPoseAtCurrentFrame); // key at 0
    s.updateFrameRangeSelectionDrag(
      layerId: cameraId,
      anchorIndex: 0,
      headIndex: 3,
    );
    expect(s.createInstancesForSelection(), isTrue);
    final camera = s.activeCutOrNull!.camera;
    for (var frame = 0; frame < 4; frame += 1) {
      expect(camera.keyframeAt(frame), isNotNull, reason: 'frame $frame');
    }
    s.undo();
    expect(s.activeCutOrNull!.camera.keyframeAt(1), isNull);
    expect(
      s.activeCutOrNull!.camera.keyframeAt(0),
      isNotNull,
      reason: 'the pre-existing key survives the undo',
    );
  });

  test('R26 #1: a span across camera + instruction + drawing rows is ONE '
      'undo step - a single undo clears every created instance', () {
    final s = session();
    final cameraId = s.layers.firstWhere((l) => l.kind == LayerKind.camera).id;
    s.addLayerOfKind(LayerKind.instruction);
    final instrId = s.activeLayer!.id;
    final drawingId = s.layers
        .firstWhere((l) => layerKindHoldsDrawings(l.kind))
        .id;

    s.updateFrameRangeSelectionDrag(
      layerId: cameraId,
      anchorIndex: 0,
      headIndex: 3,
      headLayerId: drawingId,
    );
    final span = s.frameRangeSelection.value!.spanLayerIds;
    expect(
      span,
      containsAll(<LayerId>[cameraId, instrId, drawingId]),
      reason: 'the span must cover all three row kinds for this contract',
    );
    expect(s.createInstancesForSelection(), isTrue);
    expect(s.activeCutOrNull!.camera.keyframeAt(2), isNotNull);
    expect(layerOf(s, instrId).instructions, isNotEmpty);
    expect(layerOf(s, drawingId).timeline, isNotEmpty);

    s.undo();
    expect(
      s.activeCutOrNull!.camera.keyframeAt(2),
      isNull,
      reason: 'ONE undo, not three',
    );
    expect(layerOf(s, instrId).instructions, isEmpty);
    expect(layerOf(s, drawingId).timeline, isEmpty);
  });

  test('a LANE selection freezes keys on every unkeyed frame of the '
      'range in ONE undo', () {
    final s = session();
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;
    s.updateLaneRangeSelectionDrag(
      layerId: layerId,
      laneId: 'position',
      anchorIndex: 2,
      headIndex: 4,
    );
    expect(s.createInstancesForSelection(), isTrue);
    expect(
      layerOf(s, layerId).transformTrack.position.keys.keys.toSet(),
      {2, 3, 4},
    );
    s.undo();
    expect(layerOf(s, layerId).transformTrack.position.keys, isEmpty);
  });

  test('dialog-free default creation (UI-R25 #2): the playhead SE/'
      'instruction create carries defaults directly', () {
    final s = session();
    s.addLayerOfKind(LayerKind.se);
    s.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
    expect(layerOf(s, s.activeLayer!.id).timeline[0], isNotNull);

    s.addLayerOfKind(LayerKind.instruction);
    final instrId = s.activeLayer!.id;
    s.createDefaultInstructionEventAtCurrentFrame();
    expect(layerOf(s, instrId).instructions[0], isNotNull);
    // Creation never edits: a second press on the covered cell no-ops.
    final before = layerOf(s, instrId).instructions[0];
    s.createDefaultInstructionEventAtCurrentFrame();
    expect(layerOf(s, instrId).instructions[0], same(before));
  });
}
