import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// UI-R8: frame-range selection (block-snapped) + the range move drag
/// session — channel-only previews, one undo per drag, selection follows
/// the landing.
void main() {
  /// A session with TWO blocks on layer A (frames 0 and 3, length 1 each)
  /// and an empty layer B below.
  (EditorSessionManager, Layer a, Layer b) fixture() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final layerA = s.activeLayer!;
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    s.addLayer();
    final layerB = s.activeLayer!;
    s.selectLayer(layerA.id);
    s.selectFrameIndex(0);
    return (
      s,
      s.layers.firstWhere((l) => l.id == layerA.id),
      s.layers.firstWhere((l) => l.id == layerB.id),
    );
  }

  test('a drag SNAPS to whole blocks: half-covering a block extends the '
      'selection through it', () {
    final (s, a, _) = fixture();

    // Raw drag from frame 1 (inside nothing — the blocks are at 0 and 3,
    // both length 1)… drag 0→3 half-covers nothing; drag over block cells
    // snaps outward.
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 3,
    );
    final selection = s.frameRangeSelection.value;
    expect(selection, isNotNull);
    expect(selection!.layerId, a.id);
    expect(selection.startIndex, 0);
    // The head cell (3) is a block start: the block extends the range to
    // its end.
    expect(selection.endIndexExclusive, 4);
  });

  test('EVERY layer row selects (UI-R20 #2): camera/instruction rows take '
      'raw spans and cross-section spans walk the display order; empty '
      'key rows contribute nothing to a move', () {
    final (s, a, _) = fixture();
    final camera = s.layers.firstWhere((l) => l.kind == LayerKind.camera);
    final instruction = s.layers.firstWhere(
      (l) => l.kind == LayerKind.instruction,
    );

    // Camera-origin: no blocks to snap → the raw span selects as-is.
    s.updateFrameRangeSelectionDrag(
      layerId: camera.id,
      anchorIndex: 2,
      headIndex: 5,
    );
    var selection = s.frameRangeSelection.value;
    expect(selection, isNotNull);
    expect(selection!.layerId, camera.id);
    expect(selection.startIndex, 2);
    expect(selection.endIndexExclusive, 6);
    expect(
      s.beginFrameRangeMoveDrag(),
      isFalse,
      reason:
          'no keys in range — nothing to move (P3b-2: WITH keys the '
          'camera row moves; see the key-move tests)',
    );

    // Instruction-origin too.
    s.updateFrameRangeSelectionDrag(
      layerId: instruction.id,
      anchorIndex: 0,
      headIndex: 1,
    );
    expect(s.frameRangeSelection.value!.layerId, instruction.id);

    // A drawing→camera cross-row drag spans the SECTIONED display order:
    // drawing rows, the track-SE rows, instruction, camera. Empty key
    // rows in the span are silent — the blocks still move.
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: camera.id,
    );
    selection = s.frameRangeSelection.value;
    expect(selection!.spanLayerIds.first, a.id);
    expect(selection.spanLayerIds.last, camera.id);
    expect(
      selection.spanLayerIds.length,
      greaterThanOrEqualTo(5),
      reason: 'SE + instruction rows in between join the span',
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.cancelFrameRangeMoveDrag();

    // Regression pin: a drawing-only span still moves.
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 3,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.cancelFrameRangeMoveDrag();
  });

  test('selection clears on layer switch and cut refresh', () {
    final (s, a, b) = fixture();
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(s.frameRangeSelection.value, isNotNull);

    s.selectLayer(b.id);
    expect(s.frameRangeSelection.value, isNull);
  });

  test('range move slides BOTH blocks as one rigid group: channel-only '
      'preview, one commit notify, one undo', () {
    final (s, a, _) = fixture();
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 3,
    );
    var notifies = 0;
    s.addListener(() => notifies += 1);

    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 2);

    final preview = s.dragPreview.value;
    expect(preview, isA<BlockMoveDragPreview>());
    final previewLayer = (preview as BlockMoveDragPreview).previewLayers[a.id]!;
    expect(previewLayer.timeline[0], isNull);
    expect(previewLayer.timeline[2], isNotNull);
    expect(previewLayer.timeline[5], isNotNull, reason: 'gap preserved');
    // The selection outline follows the previewed landing.
    expect(s.frameRangeSelection.value!.startIndex, 2);
    expect(s.frameRangeSelection.value!.endIndexExclusive, 6);
    // Repository untouched, no session notify per step.
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[0], isNotNull);
    expect(notifies, 0);

    s.endFrameRangeMoveDrag();
    expect(s.dragPreview.value, isNull);
    expect(notifies, 1);
    final moved = s.layers.firstWhere((l) => l.id == a.id);
    expect(moved.timeline[2], isNotNull);
    expect(moved.timeline[5], isNotNull);
    expect(moved.timeline[0], isNull);
    // The selection stays on the landed frames.
    expect(s.frameRangeSelection.value!.startIndex, 2);

    s.undo();
    final back = s.layers.firstWhere((l) => l.id == a.id);
    expect(back.timeline[0], isNotNull);
    expect(back.timeline[3], isNotNull);
    expect(back.timeline[2], isNull);
  });

  test('cross-layer range move carries BOTH cels, re-keys the store, one '
      'undo restores everything', () {
    final (s, a, b) = fixture();
    final frameIds = [a.timeline[0]!.frameId!, a.timeline[3]!.frameId!];
    final cut = s.requireActiveCut;
    final fromKeys = [
      for (final id in frameIds) s.brushFrameKeyForCut(cut, a.id, id),
    ];
    final toKeys = [
      for (final id in frameIds) s.brushFrameKeyForCut(cut, b.id, id),
    ];
    for (final key in fromKeys) {
      s.brushFrameStore.getOrCreateFrame(key);
    }

    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 3,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: b.id);
    s.endFrameRangeMoveDrag();

    expect(s.activeLayer!.id, b.id, reason: 'selection follows the frames');
    final movedA = s.layers.firstWhere((l) => l.id == a.id);
    final movedB = s.layers.firstWhere((l) => l.id == b.id);
    expect(movedA.timeline, isEmpty);
    expect(movedB.timeline[0], isNotNull);
    expect(movedB.timeline[3], isNotNull);
    for (var i = 0; i < frameIds.length; i += 1) {
      expect(s.brushFrameStore.frameOrNull(fromKeys[i]), isNull);
      expect(s.brushFrameStore.frameOrNull(toKeys[i]), isNotNull);
    }

    s.undo();
    final backA = s.layers.firstWhere((l) => l.id == a.id);
    final backB = s.layers.firstWhere((l) => l.id == b.id);
    expect(backA.timeline[0], isNotNull);
    expect(backA.timeline[3], isNotNull);
    expect(backB.timeline, isEmpty);
    for (var i = 0; i < frameIds.length; i += 1) {
      expect(s.brushFrameStore.frameOrNull(fromKeys[i]), isNotNull);
      expect(s.brushFrameStore.frameOrNull(toKeys[i]), isNull);
    }
  });

  test('P3b-2 (#2 second half): camera keys RIDE the range move — live '
      'preview through the cell resolution, one undo, and a colliding '
      'landing voids the whole move', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final camera = s.layers.firstWhere((l) => l.kind == LayerKind.camera);
    s.selectLayer(camera.id);
    s.selectFrameIndex(2);
    s.setCameraKeyframeAtCurrentFrame(s.cameraPoseAtCurrentFrame);
    s.selectFrameIndex(4);
    s.setCameraKeyframeAtCurrentFrame(s.cameraPoseAtCurrentFrame);

    // Select the camera row across both keys and slide +3.
    s.updateFrameRangeSelectionDrag(
      layerId: camera.id,
      anchorIndex: 2,
      headIndex: 4,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 3);
    // The cells follow the preview keys while the repository stays put.
    expect(
      s.exposureStateForLayer(camera, 5),
      TimelineCellExposureState.drawingStart,
    );
    expect(
      s.exposureStateForLayer(camera, 2),
      TimelineCellExposureState.uncovered,
    );
    expect(s.activeCutOrNull!.camera.keyframeAt(2), isNotNull);

    s.endFrameRangeMoveDrag();
    expect(s.activeCutOrNull!.camera.keyframeAt(5), isNotNull);
    expect(s.activeCutOrNull!.camera.keyframeAt(7), isNotNull);
    expect(s.activeCutOrNull!.camera.keyframeAt(2), isNull);

    // ONE undo restores both keys.
    s.undo();
    expect(s.activeCutOrNull!.camera.keyframeAt(2), isNotNull);
    expect(s.activeCutOrNull!.camera.keyframeAt(4), isNotNull);

    // A landing on an unmoved key voids: select just the key at 2, slide
    // +2 (onto 4) — the preview clears and the end commits nothing.
    s.updateFrameRangeSelectionDrag(
      layerId: camera.id,
      anchorIndex: 2,
      headIndex: 2,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 2);
    expect(s.dragPreview.value, isNull);
    final undoDepth = s.canUndo;
    s.endFrameRangeMoveDrag();
    expect(s.activeCutOrNull!.camera.keyframeAt(2), isNotNull);
    expect(s.canUndo, undoDepth, reason: 'void moves commit nothing');
  });

  test('P3b-2: instruction spans ride the range move too — shifted rows '
      'preview as substituted layers and commit in the same undo', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final instruction = s.layers.firstWhere(
      (l) => l.kind == LayerKind.instruction,
    );
    s.repository.updateLayerInstructions(
      cutId: s.requireActiveCut.id,
      layerId: instruction.id,
      instructions: const {
        1: InstructionEvent(instructionId: 'pan', length: 2),
      },
    );

    s.updateFrameRangeSelectionDrag(
      layerId: instruction.id,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 4);
    final preview = s.dragPreview.value;
    expect(preview, isA<BlockMoveDragPreview>());
    final previewLayer =
        (preview as BlockMoveDragPreview).previewLayers[instruction.id];
    expect(previewLayer!.instructions.containsKey(5), isTrue);

    s.endFrameRangeMoveDrag();
    final moved = s.layers.firstWhere((l) => l.id == instruction.id);
    expect(moved.instructions.containsKey(5), isTrue);
    expect(moved.instructions.containsKey(1), isFalse);
    s.undo();
    expect(
      s.layers
          .firstWhere((l) => l.id == instruction.id)
          .instructions
          .containsKey(1),
      isTrue,
    );
  });

  test('UI-R23 #3: a frame-range move does NOT carry the layer\'s own '
      'transform keys (frame selection ⊥ transform keys), and a key-only '
      'span has nothing to move', () {
    final (s, a, _) = fixture();
    // Key the position lane at frames 0 and 3 (where the blocks sit).
    s.repository.replaceLayer(
      layer: a.copyWith(
        transformTrack: TransformTrack.properties(
          anchorPoint: PropertyTrack.empty(),
          position: PropertyTrack<CanvasPoint>()
              .withKey(0, CanvasPoint(x: 1, y: 1))
              .withKey(3, CanvasPoint(x: 2, y: 2)),
          scale: PropertyTrack.empty(),
          rotation: PropertyTrack.empty(),
          opacity: PropertyTrack.empty(),
        ),
      ),
    );

    // The blocks slide (+2) but the transform keys STAY put.
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 3,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 2);
    final preview = s.dragPreview.value! as BlockMoveDragPreview;
    expect(
      preview.previewLayers[a.id]!.transformTrack.position.keys.keys.toSet(),
      {0, 3},
      reason: 'the transform keys do NOT ride the frame move',
    );
    s.endFrameRangeMoveDrag();
    final moved = s.layers.firstWhere((l) => l.id == a.id);
    expect(moved.timeline.containsKey(2), isTrue);
    expect(moved.transformTrack.position.keys.keys.toSet(), {0, 3});

    // A span over EMPTY cells holding ONLY a transform key can't move —
    // frame selection no longer picks transform keys up.
    s.repository.replaceLayer(
      layer: s.layers
          .firstWhere((l) => l.id == a.id)
          .copyWith(
            transformTrack: TransformTrack.properties(
              anchorPoint: PropertyTrack.empty(),
              position: PropertyTrack<CanvasPoint>().withKey(
                8,
                CanvasPoint(x: 3, y: 3),
              ),
              scale: PropertyTrack.empty(),
              rotation: PropertyTrack.empty(),
              opacity: PropertyTrack.empty(),
            ),
          ),
    );
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 8,
      headIndex: 8,
    );
    expect(
      s.beginFrameRangeMoveDrag(),
      isFalse,
      reason: 'a key-only span has no blocks to move',
    );
    expect(
      s.layers
          .firstWhere((l) => l.id == a.id)
          .transformTrack
          .position
          .keys
          .keys
          .toSet(),
      {8},
    );
  });

  test('P3b-3 (#2): cross-row drops land within the SAME SECTION now — '
      'animation ↔ storyboard/art interchange', () {
    final (s, a, _) = fixture();
    s.addLayerOfKind(LayerKind.storyboard);
    final storyboard = s.activeLayer!;
    s.selectLayer(a.id);

    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: storyboard.id);
    s.endFrameRangeMoveDrag();

    final landed = s.layers.firstWhere((l) => l.id == storyboard.id);
    expect(
      landed.timeline.containsKey(0),
      isTrue,
      reason: 'the block landed on the storyboard-kind row',
    );
    expect(
      s.layers.firstWhere((l) => l.id == a.id).timeline.containsKey(0),
      isFalse,
    );
  });

  test('UI-R22 #4: covering ONE cell of an instruction event selects its '
      'whole span (the block rule on CAM rows)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final instruction = s.layers.firstWhere(
      (l) => l.kind == LayerKind.instruction,
    );
    s.repository.updateLayerInstructions(
      cutId: s.requireActiveCut.id,
      layerId: instruction.id,
      instructions: const {
        1: InstructionEvent(instructionId: 'pan', length: 3),
        7: InstructionEvent(instructionId: 'zoom', length: 2),
      },
    );

    // One mid-event cell → the whole [1,4) span.
    s.updateFrameRangeSelectionDrag(
      layerId: instruction.id,
      anchorIndex: 2,
      headIndex: 2,
    );
    var selection = s.frameRangeSelection.value!;
    expect(selection.startIndex, 1);
    expect(selection.endIndexExclusive, 4);

    // A sweep half-covering the second event swallows it whole.
    s.updateFrameRangeSelectionDrag(
      layerId: instruction.id,
      anchorIndex: 2,
      headIndex: 7,
    );
    selection = s.frameRangeSelection.value!;
    expect(selection.startIndex, 1);
    expect(selection.endIndexExclusive, 9);
  });

  test('P3b-4 (#2): SE→SE row moves land blocks WITH their cels and '
      'audio clips on the sibling SE row — one undo restores both rows', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final seIds = [for (final l in s.activeTrack.seLayers) l.id];
    expect(seIds, hasLength(2));
    final s1 = s.activeTrack.seLayers.first;
    s.repository.replaceLayer(
      layer: s1.copyWith(
        frames: [
          Frame(id: const FrameId('se-cel'), duration: 1, strokes: const []),
        ],
        timeline: const {
          2: TimelineExposure.drawing(FrameId('se-cel'), length: 3),
        },
        audioClips: const [
          AudioClip(filePath: 'a.wav', frameId: FrameId('se-cel')),
        ],
      ),
    );

    s.updateFrameRangeSelectionDrag(
      layerId: seIds[0],
      anchorIndex: 2,
      headIndex: 4,
    );
    expect(s.frameRangeSelection.value, isNotNull);
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: seIds[1]);
    final preview = s.dragPreview.value! as BlockMoveDragPreview;
    expect(preview.previewLayers.keys.toSet(), seIds.toSet());
    s.endFrameRangeMoveDrag();

    Layer seLayer(int index) =>
        s.activeTrack.seLayers.firstWhere((l) => l.id == seIds[index]);
    expect(seLayer(0).timeline, isEmpty);
    expect(seLayer(0).audioClips, isEmpty);
    expect(seLayer(1).timeline.containsKey(2), isTrue);
    expect(seLayer(1).frames.single.id, const FrameId('se-cel'));
    expect(
      seLayer(1).audioClips.single.frameId,
      const FrameId('se-cel'),
      reason: 'the clip follows its cel to the landing row',
    );
    expect(s.activeLayer!.id, seIds[1], reason: 'selection follows');

    s.undo();
    expect(seLayer(0).timeline.containsKey(2), isTrue);
    expect(seLayer(0).audioClips, hasLength(1));
    expect(seLayer(1).timeline, isEmpty);
  });

  test('P3b-4 (#2): instruction→instruction row moves carry the events; '
      'an overlapping landing voids; cross-kind hovers clear the preview', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final first = s.layers.firstWhere((l) => l.kind == LayerKind.instruction);
    s.addLayerOfKind(LayerKind.instruction);
    final second = s.layers.lastWhere(
      (l) => l.kind == LayerKind.instruction && l.id != first.id,
    );
    s.repository.updateLayerInstructions(
      cutId: s.requireActiveCut.id,
      layerId: first.id,
      instructions: const {
        1: InstructionEvent(instructionId: 'pan', length: 2),
      },
    );

    s.updateFrameRangeSelectionDrag(
      layerId: first.id,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 2, targetLayerId: second.id);
    expect(s.dragPreview.value, isNotNull);
    s.endFrameRangeMoveDrag();

    Layer row(LayerId id) => s.layers.firstWhere((l) => l.id == id);
    expect(row(first.id).instructions, isEmpty);
    expect(row(second.id).instructions.containsKey(3), isTrue);
    s.undo();
    expect(row(first.id).instructions.containsKey(1), isTrue);
    expect(row(second.id).instructions, isEmpty);

    // An overlapping landing on the target voids the drop.
    s.repository.updateLayerInstructions(
      cutId: s.requireActiveCut.id,
      layerId: second.id,
      instructions: const {
        2: InstructionEvent(instructionId: 'zoom', length: 2),
      },
    );
    s.updateFrameRangeSelectionDrag(
      layerId: first.id,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 2, targetLayerId: second.id);
    expect(s.dragPreview.value, isNull, reason: '[3,5) overlaps [2,4)');
    final undoProbe = s.canUndo;
    s.endFrameRangeMoveDrag();
    expect(s.canUndo, undoProbe, reason: 'void drops commit nothing');

    // A cross-kind hover (instruction → drawing row) clears the preview.
    final drawing = s.layers.firstWhere((l) => l.kind == LayerKind.animation);
    s.updateFrameRangeSelectionDrag(
      layerId: first.id,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 1, targetLayerId: drawing.id);
    expect(s.dragPreview.value, isNull);
    s.cancelFrameRangeMoveDrag();
  });

  test('GHOST exposures are TEXT-ONLY (UI-R23 #6): repeat instances never '
      'extend a snap, a ghost press selects the one cell, and the real '
      'source still slides with its ghosts re-derived at the landing', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;
    // Author a repeat edge after the single 1-frame block at 0 (UI-R9
    // #10: ghosts fill to the cut end).
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    final layer = s.layers.firstWhere((l) => l.id == layerId);
    expect(layer.timeline[1]!.ghost, isTrue);
    expect(layer.timeline[2]!.ghost, isTrue);

    // The sweep spans the raw drag: the real block at 0 is covered, the
    // ghosts read as empty cells and never extend the span past the head.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(s.frameRangeSelection.value!.startIndex, 0);
    expect(s.frameRangeSelection.value!.endIndexExclusive, 3);

    // A drag STARTING on a ghost selects that ghost cell alone (empty-cell
    // semantics — no expansion into the derived run).
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 2,
      headIndex: 2,
    );
    expect(s.frameRangeSelection.value!.startIndex, 2);
    expect(s.frameRangeSelection.value!.endIndexExclusive, 3);

    // A move over a ghost-covering selection slides the REAL source and
    // re-derives the ghosts at the landing.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 4);
    s.endFrameRangeMoveDrag();
    final moved = s.layers.firstWhere((l) => l.id == layerId);
    expect(moved.timeline[4]!.ghost, isFalse);
    expect(moved.timeline[5]!.ghost, isTrue);
    expect(moved.timeline[6]!.ghost, isTrue);
    expect(moved.timeline.containsKey(1), isFalse);

    // A GHOST-ONLY selection has nothing real to move — the begin refuses.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 6,
      headIndex: 6,
    );
    expect(s.frameRangeSelection.value, isNotNull);
    expect(s.beginFrameRangeMoveDrag(), isFalse);
  });

  test('a HOLD-edge ghost (one multi-frame span) never swallows the '
      'selection (UI-R23 #6): a press deep inside it selects one cell', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );
    final layer = s.layers.firstWhere((l) => l.id == layerId);
    // Hold fills [1, cutEnd) as ONE multi-frame ghost — the case where the
    // old block-snap would have swallowed the whole derived span.
    expect(layer.timeline[1]!.ghost, isTrue);
    expect(layer.timeline[1]!.length!, greaterThan(1));

    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 5,
      headIndex: 5,
    );
    expect(s.frameRangeSelection.value!.startIndex, 5);
    expect(s.frameRangeSelection.value!.endIndexExclusive, 6);
  });

  test('a REPEAT-edge block ROW-MOVES to another layer (UI-R23 #5): the '
      'derived ghosts sharing its cel no longer void the cross-row drop', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final aId = s.activeLayer!.id;
    s.setRunEdgeBehavior(
      layerId: aId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    s.addLayer();
    final bId = s.activeLayer!.id;

    // Select the REAL block on A and drop it on the empty layer B.
    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(layerId: aId, anchorIndex: 0, headIndex: 0);
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(
      s.dragPreview.value,
      isNotNull,
      reason: 'the cross-row drop is legal now (ghosts are not real links)',
    );
    s.endFrameRangeMoveDrag();

    final aAfter = s.layers.firstWhere((l) => l.id == aId);
    final bAfter = s.layers.firstWhere((l) => l.id == bId);
    // The real block landed on B; A no longer owns it (and, with its
    // anchor gone, the repeat behavior self-heals away).
    expect(bAfter.timeline[0]!.ghost, isFalse);
    expect(aAfter.timeline.containsKey(0), isFalse);
  });

  test('a blocked / incompatible landing HOLDS the last valid preview '
      '(UI-R23 #10): a row-move stops at the last legal spot and resumes on '
      'return — it never snaps back to the origin', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final aId = s.activeLayer!.id;
    s.addLayer();
    final bId = s.activeLayer!.id;
    final camId = s.layers.firstWhere((l) => l.kind == LayerKind.camera).id;

    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(layerId: aId, anchorIndex: 0, headIndex: 0);
    expect(s.beginFrameRangeMoveDrag(), isTrue);

    // A valid drop on B: preview + outline follow to B.
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(s.dragPreview.value, isNotNull);
    expect(s.frameRangeSelection.value!.layerId, bId);

    // Wander onto the incompatible camera section: the last valid landing
    // HOLDS (preview stays, outline stays on B) — no snap-back to A.
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: camId);
    expect(
      s.dragPreview.value,
      isNotNull,
      reason: 'a blocked hover keeps the last valid preview',
    );
    expect(s.frameRangeSelection.value!.layerId, bId);

    // Return to B resumes cleanly; the release commits on B.
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(s.frameRangeSelection.value!.layerId, bId);
    s.endFrameRangeMoveDrag();
    final aAfter = s.layers.firstWhere((l) => l.id == aId);
    final bAfter = s.layers.firstWhere((l) => l.id == bId);
    expect(bAfter.timeline.containsKey(0), isTrue);
    expect(aAfter.timeline.containsKey(0), isFalse);
  });

  test('a multi-layer drawing selection ROW-MOVES as one rigid group '
      '(UI-R23 #9): every selected row shifts together, cels travel, and one '
      'undo restores all rows', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame(); // block on A
    final aId = s.activeLayer!.id;
    s.addLayer();
    final bId = s.activeLayer!.id;
    s.selectLayer(bId);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame(); // block on B
    s.addLayer();
    final cId = s.activeLayer!.id; // empty target row below

    Layer layer(LayerId id) => s.layers.firstWhere((l) => l.id == id);
    final aFrameId = layer(aId).frames.single.id;
    final bFrameId = layer(bId).frames.single.id;

    // Select A..B, then drag the anchor down one row (A->B, B->C).
    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(
      layerId: aId,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: bId,
    );
    expect(s.frameRangeSelection.value!.spanLayerIds, [aId, bId]);
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(s.dragPreview.value, isNotNull);
    expect(s.frameRangeSelection.value!.spanLayerIds, [bId, cId]);
    s.endFrameRangeMoveDrag();

    // The whole group shifted down one row; cels rode along.
    expect(layer(aId).timeline.keys, isEmpty);
    expect(layer(bId).timeline[0]!.frameId, aFrameId);
    expect(layer(cId).timeline[0]!.frameId, bFrameId);
    expect(layer(bId).frames.map((f) => f.id), contains(aFrameId));
    expect(layer(cId).frames.map((f) => f.id), contains(bFrameId));

    // ONE undo restores every affected row.
    s.undo();
    expect(layer(aId).timeline[0]!.frameId, aFrameId);
    expect(layer(bId).timeline[0]!.frameId, bFrameId);
    expect(layer(cId).timeline.keys, isEmpty);
  });

  test('R26 #2: a MULTI-ROW selection that also covers an SE row carries '
      'that row to its sibling SE row — one undo restores everything', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame(); // block on A at frame 0
    final aId = s.activeLayer!.id;
    s.addLayer();
    final bId = s.activeLayer!.id; // empty drawing row below A

    final seIds = [for (final l in s.activeTrack.seLayers) l.id];
    expect(seIds, hasLength(2));
    s.repository.replaceLayer(
      layer: s.activeTrack.seLayers.first.copyWith(
        frames: [
          Frame(id: const FrameId('se-cel'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('se-cel'), length: 1),
        },
        audioClips: const [
          AudioClip(filePath: 'a.wav', frameId: FrameId('se-cel')),
        ],
      ),
    );

    Layer layer(LayerId id) => s.layers.firstWhere((l) => l.id == id);
    Layer seLayer(int index) =>
        s.activeTrack.seLayers.firstWhere((l) => l.id == seIds[index]);
    final aFrameId = layer(aId).frames.single.id;

    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(
      layerId: aId,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: seIds[0],
    );
    final span = s.frameRangeSelection.value!.spanLayerIds;
    expect(span, containsAll(<LayerId>[aId, seIds[0]]));
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    final preview = s.dragPreview.value! as BlockMoveDragPreview;
    expect(
      preview.previewLayers.keys,
      containsAll(<LayerId>[seIds[0], seIds[1]]),
      reason: 'the SE passenger previews on both SE rows',
    );
    s.endFrameRangeMoveDrag();

    expect(layer(aId).timeline, isEmpty);
    expect(layer(bId).timeline[0]!.frameId, aFrameId);
    expect(
      seLayer(0).timeline,
      isEmpty,
      reason: 'the SE row travelled with the rigid shift (R26 #2)',
    );
    expect(seLayer(1).timeline.containsKey(0), isTrue);
    expect(seLayer(1).audioClips.single.frameId, const FrameId('se-cel'));

    s.undo();
    expect(layer(aId).timeline[0]!.frameId, aFrameId);
    expect(seLayer(0).timeline.containsKey(0), isTrue);
    expect(seLayer(1).timeline, isEmpty);
  });

  test('a multi-row shift that would push a row off the lattice HOLDS the '
      'last valid landing (UI-R23 #9 + #10)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final aId = s.activeLayer!.id;
    s.addLayer();
    final bId = s.activeLayer!.id;
    s.selectLayer(bId);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.addLayer();
    final cId = s.activeLayer!.id;

    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(
      layerId: aId,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: bId,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    // A valid one-row shift (A->B, B->C).
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(s.frameRangeSelection.value!.spanLayerIds, [bId, cId]);

    // Dragging further so B would fall off the bottom is illegal — the last
    // valid one-row shift HOLDS (no snap-back, no partial move).
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: cId);
    expect(s.frameRangeSelection.value!.spanLayerIds, [bId, cId]);
    expect(s.dragPreview.value, isNotNull);
    s.cancelFrameRangeMoveDrag();
  });

  test('a span with EMPTY rows row-moves its content (UI-R24 #3): '
      'selecting two layers where only one holds blocks still lands the '
      'blocks on the target row', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame(); // block on A
    final aId = s.activeLayer!.id;
    s.addLayer();
    final bId = s.activeLayer!.id; // stays EMPTY, joins the selection
    s.addLayer();
    final cId = s.activeLayer!.id; // target row

    s.selectLayer(aId);
    s.updateFrameRangeSelectionDrag(
      layerId: aId,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: bId,
    );
    expect(s.frameRangeSelection.value!.spanLayerIds, [aId, bId]);
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    // Drag down one row: A's block lands on B; the empty B maps to C but
    // carries nothing — the move must NOT refuse.
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: bId);
    expect(
      s.dragPreview.value,
      isNotNull,
      reason: 'empty selected rows never block the row move',
    );
    s.endFrameRangeMoveDrag();

    Layer layer(LayerId id) => s.layers.firstWhere((l) => l.id == id);
    expect(layer(aId).timeline.keys, isEmpty);
    expect(layer(bId).timeline.containsKey(0), isTrue);
    expect(layer(cId).timeline.keys, isEmpty);
  });

  test('the LANE selection domain (UI-R23 #3 part 2): a lane span selects '
      'independently, moves ONLY that lane\'s keys as one undo, holds on a '
      'blocked landing, and is mutually exclusive with the cell selection', () {
    final (s, a, _) = fixture();
    s.repository.replaceLayer(
      layer: s.layers
          .firstWhere((l) => l.id == a.id)
          .copyWith(
            transformTrack: TransformTrack.properties(
              anchorPoint: PropertyTrack.empty(),
              position: PropertyTrack<CanvasPoint>()
                  .withKey(2, CanvasPoint(x: 1, y: 1))
                  .withKey(8, CanvasPoint(x: 9, y: 9)),
              scale: PropertyTrack<double>().withKey(2, 1.5),
              rotation: PropertyTrack.empty(),
              opacity: PropertyTrack.empty(),
            ),
          ),
    );

    // A lane span selects the (layer, lane) domain — raw cells.
    s.updateLaneRangeSelectionDrag(
      layerId: a.id,
      laneId: 'position',
      anchorIndex: 1,
      headIndex: 3,
    );
    final selection = s.laneRangeSelection.value;
    expect(selection, isNotNull);
    expect(selection!.laneId, 'position');
    expect(selection.startIndex, 1);
    expect(selection.endIndexExclusive, 4);

    // Starting a CELL selection clears the lane selection — and back.
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(s.laneRangeSelection.value, isNull);
    expect(s.frameRangeSelection.value, isNotNull);
    s.updateLaneRangeSelectionDrag(
      layerId: a.id,
      laneId: 'position',
      anchorIndex: 1,
      headIndex: 3,
    );
    expect(s.frameRangeSelection.value, isNull);

    // The move shifts ONLY the position lane's covered key (+2): the
    // scale key at 2 and the position key at 8 stay put.
    expect(s.beginLaneRangeMoveDrag(), isTrue);
    s.updateLaneRangeMoveDrag(frameDelta: 2);
    expect(s.dragPreview.value, isNotNull);
    // A blocked further step (landing on the unmoved key at 8: 2+2 range
    // would collide at... use a big delta landing 2->8) HOLDS the last
    // valid preview (UI-R23 #10).
    s.updateLaneRangeMoveDrag(frameDelta: 6);
    expect(s.laneRangeSelection.value!.startIndex, 3, reason: 'held at +2');
    s.endLaneRangeMoveDrag();

    Layer layer() => s.layers.firstWhere((l) => l.id == a.id);
    expect(layer().transformTrack.position.keys.keys.toSet(), {4, 8});
    expect(layer().transformTrack.scale.keys.keys.toSet(), {2});

    // ONE undo restores the lane.
    s.undo();
    expect(layer().transformTrack.position.keys.keys.toSet(), {2, 8});
  });

  test('a REFUSED lane-move begin leaves the drag in flight alone', () {
    // 🚨The same law the block move wears, pinned on the family that also
    // moved to a drag object: a begin that refuses must not touch a drag
    // already running. The first wiring of the drag-session type wrote null
    // over a live drag and stranded its preview in the channel.
    //
    // The second begin here refuses at the KEYED gate — the selection moved
    // onto a lane with no keys in range — which is the reachable refusal
    // for this family.
    final (s, a, _) = fixture();
    s.repository.replaceLayer(
      layer: s.layers
          .firstWhere((l) => l.id == a.id)
          .copyWith(
            transformTrack: TransformTrack.properties(
              anchorPoint: PropertyTrack.empty(),
              position: PropertyTrack<CanvasPoint>().withKey(
                2,
                CanvasPoint(x: 1, y: 1),
              ),
              scale: PropertyTrack.empty(),
              rotation: PropertyTrack.empty(),
              opacity: PropertyTrack.empty(),
            ),
          ),
    );
    s.updateLaneRangeSelectionDrag(
      layerId: a.id,
      laneId: 'position',
      anchorIndex: 1,
      headIndex: 3,
    );
    expect(s.beginLaneRangeMoveDrag(), isTrue);
    s.updateLaneRangeMoveDrag(frameDelta: 2);
    expect(s.dragPreview.value, isNotNull, reason: 'a move is in flight');

    // A keyless span on the SAME row: nothing to move, so the begin refuses.
    s.updateLaneRangeSelectionDrag(
      layerId: a.id,
      laneId: 'scale',
      anchorIndex: 1,
      headIndex: 3,
    );
    expect(s.beginLaneRangeMoveDrag(), isFalse);
    expect(
      s.dragPreview.value,
      isNotNull,
      reason: 'the refusal is not a cancel — the live drag kept its preview',
    );

    // And the original drag still closes the normal way.
    s.cancelLaneRangeMoveDrag();
    expect(s.dragPreview.value, isNull);
  });

  test('R26 #3: a lane span covers MULTIPLE lane rows (headLaneId), the '
      'group header anchors the whole group, and the move shifts every '
      'spanned lane as one rigid undo', () {
    final (s, a, _) = fixture();
    s.repository.replaceLayer(
      layer: s.layers
          .firstWhere((l) => l.id == a.id)
          .copyWith(
            transformTrack: TransformTrack.properties(
              anchorPoint: PropertyTrack.empty(),
              position: PropertyTrack<CanvasPoint>().withKey(
                2,
                CanvasPoint(x: 1, y: 1),
              ),
              scale: PropertyTrack<double>().withKey(3, 1.5),
              rotation: PropertyTrack<double>().withKey(9, 45),
              opacity: PropertyTrack.empty(),
            ),
          ),
    );

    // A cross-row drag position→scale spans both lanes.
    s.updateLaneRangeSelectionDrag(
      layerId: a.id,
      laneId: 'position',
      anchorIndex: 1,
      headIndex: 4,
      headLaneId: 'scale',
    );
    final span = s.laneRangeSelection.value!;
    expect(span.spanLaneIds, ['position', 'scale']);
    expect(span.coversLane(a.id, 'scale'), isTrue);
    expect(span.coversLane(a.id, 'rotation'), isFalse);

    // The move shifts BOTH covered keys (+2) in one undo; the rotation
    // key outside the span stays put.
    expect(s.beginLaneRangeMoveDrag(), isTrue);
    s.updateLaneRangeMoveDrag(frameDelta: 2);
    s.endLaneRangeMoveDrag();
    Layer layer() => s.layers.firstWhere((l) => l.id == a.id);
    expect(layer().transformTrack.position.keys.keys.toSet(), {4});
    expect(layer().transformTrack.scale.keys.keys.toSet(), {5});
    expect(layer().transformTrack.rotation.keys.keys.toSet(), {9});
    s.undo();
    expect(layer().transformTrack.position.keys.keys.toSet(), {2});
    expect(layer().transformTrack.scale.keys.keys.toSet(), {3});

    // R9 #20: a drag along the HEADER row alone selects the header row
    // alone — selection covers what the drag drew. The MOVE still grabs
    // every member lane's keys, because the header band is what shows
    // them (follow-up: 한번에 잡아 이동). Keeping those two apart is the
    // whole of #20.
    s.updateLaneRangeSelectionDrag(
      layerId: a.id,
      laneId: 'transform-group',
      anchorIndex: 0,
      headIndex: 4,
    );
    expect(s.laneRangeSelection.value!.spanLaneIds, ['transform-group']);
    expect(s.beginLaneRangeMoveDrag(), isTrue);
    s.updateLaneRangeMoveDrag(frameDelta: 3);
    s.endLaneRangeMoveDrag();
    expect(layer().transformTrack.position.keys.keys.toSet(), {5});
    expect(layer().transformTrack.scale.keys.keys.toSet(), {6});
    expect(
      layer().transformTrack.rotation.keys.keys.toSet(),
      {9},
      reason: 'the rotation key at 9 sits outside the [0,5) range',
    );
    s.undo();
  });

  test('R26 #3: selecting ANOTHER layer\'s lane rows activates that layer; '
      'the active layer\'s own lanes leave it unchanged', () {
    final (s, a, b) = fixture();
    expect(s.activeLayerId, a.id);

    // Lanes of the ACTIVE layer: selection lands, active layer holds.
    s.updateLaneRangeSelectionDrag(
      layerId: a.id,
      laneId: 'position',
      anchorIndex: 0,
      headIndex: 1,
    );
    expect(s.activeLayerId, a.id);
    expect(s.laneRangeSelection.value!.layerId, a.id);

    // Another layer's lanes: the active layer FOLLOWS (원문: 다른
    // 레이어의 fx행쪽 선택하면 액티브 레이어는 바뀜) and the fresh
    // selection survives the switch.
    s.updateLaneRangeSelectionDrag(
      layerId: b.id,
      laneId: 'position',
      anchorIndex: 0,
      headIndex: 1,
    );
    expect(s.activeLayerId, b.id);
    expect(s.laneRangeSelection.value!.layerId, b.id);
  });

  group('R27 #8: the row hop is a DISPLAY fact, not a lattice one', () {
    /// The reported layout: A · S1 · S2 · CAM1 (the default cut's rows),
    /// with one sound block sitting on S2.
    (EditorSessionManager, List<LayerId> se, LayerId cam) soundOnS2() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final seIds = [for (final l in s.activeTrack.seLayers) l.id];
      expect(seIds, hasLength(2));
      s.repository.replaceLayer(
        layer: s.activeTrack.seLayers[1].copyWith(
          frames: [
            Frame(id: const FrameId('se-cel'), duration: 1, strokes: const []),
          ],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('se-cel'), length: 1),
          },
        ),
      );
      final cam = s.layers
          .firstWhere((l) => l.kind == LayerKind.instruction)
          .id;
      return (s, seIds, cam);
    }

    Layer seRow(EditorSessionManager s, LayerId id) =>
        s.activeTrack.seLayers.firstWhere((l) => l.id == id);

    test('a span ANCHORED on the CAM row still carries the sound block to '
        'the empty S1 — the anchor row owns no lattice, which used to '
        'kill the whole move', () {
      final (s, seIds, cam) = soundOnS2();

      // Drag out the selection from CAM1 up over S2: the anchor is the
      // CAM row, which is on neither the drawing nor the SE lattice.
      s.updateFrameRangeSelectionDrag(
        layerId: cam,
        anchorIndex: 0,
        headIndex: 0,
        headLayerId: seIds[1],
      );
      expect(
        s.frameRangeSelection.value!.spanLayerIds,
        containsAll(<LayerId>[seIds[1], cam]),
      );
      expect(s.frameRangeSelection.value!.layerId, cam);

      // The pointer went down on the SOUND block (S2) — that row, not the
      // selection's anchor, is what lands on the row under the pointer.
      expect(s.beginFrameRangeMoveDrag(seIds[1]), isTrue);
      s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: seIds[0]);
      s.endFrameRangeMoveDrag();

      expect(seRow(s, seIds[1]).timeline, isEmpty, reason: 'the sound left S2');
      expect(seRow(s, seIds[0]).timeline.containsKey(0), isTrue);

      s.undo();
      expect(seRow(s, seIds[1]).timeline.containsKey(0), isTrue);
      expect(seRow(s, seIds[0]).timeline, isEmpty);
    });

    test('a CAM row carrying instruction keys RIDES the frame axis instead '
        'of vetoing the row move', () {
      final (s, seIds, cam) = soundOnS2();
      // Put an instruction event inside the selected range.
      final camLayer = s.layers.firstWhere((l) => l.id == cam);
      s.repository.replaceLayer(
        layer: camLayer.copyWith(
          instructions: const {
            0: InstructionEvent(instructionId: 'pan', length: 1),
          },
        ),
      );

      s.updateFrameRangeSelectionDrag(
        layerId: seIds[1],
        anchorIndex: 0,
        headIndex: 0,
        headLayerId: cam,
      );
      expect(s.beginFrameRangeMoveDrag(), isTrue);
      // Up one row AND one frame right: the sound changes rows, the
      // instruction key stays on CAM1 but travels the frame delta.
      s.updateFrameRangeMoveDrag(frameDelta: 1, targetLayerId: seIds[0]);
      s.endFrameRangeMoveDrag();

      expect(seRow(s, seIds[1]).timeline, isEmpty);
      expect(seRow(s, seIds[0]).timeline.containsKey(1), isTrue);
      final camAfter = s.layers.firstWhere((l) => l.id == cam);
      expect(camAfter.instructions.containsKey(1), isTrue);
      expect(camAfter.instructions.containsKey(0), isFalse);

      // ONE undo puts both back.
      s.undo();
      expect(seRow(s, seIds[1]).timeline.containsKey(0), isTrue);
      expect(
        s.layers.firstWhere((l) => l.id == cam).instructions.containsKey(0),
        isTrue,
      );
    });
  });

  test('R28 #5: dragging back to the START returns the block home — a zero '
      'delta is the origin, not a blocked landing', () {
    final (s, a, _) = fixture();
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);

    // Out to the right…
    s.updateFrameRangeMoveDrag(frameDelta: 2);
    expect(s.dragPreview.value, isNotNull);
    expect(s.frameRangeSelection.value!.startIndex, 2);

    // …and back home. This used to read as "blocked" — planDrawingRangeMove
    // answers null for a no-op exactly as it does for an impossible
    // landing — so the preview HELD at +2 and the block refused to come
    // back: "더 이상 왼쪽으로 이동이 안먹혀버리고 그 자리에서 멈춰버린다".
    s.updateFrameRangeMoveDrag(frameDelta: 0);
    expect(
      s.dragPreview.value,
      isNull,
      reason: 'R28 #5: at zero delta the block shows at its REAL position',
    );
    expect(
      s.frameRangeSelection.value!.startIndex,
      0,
      reason: 'the outline comes home with it',
    );

    // …and the drag still works afterwards, in both directions.
    s.updateFrameRangeMoveDrag(frameDelta: 1);
    expect(s.frameRangeSelection.value!.startIndex, 1);
    s.updateFrameRangeMoveDrag(frameDelta: 0);
    expect(s.frameRangeSelection.value!.startIndex, 0);

    s.endFrameRangeMoveDrag();
    // Ending at the origin commits nothing.
    expect(
      s.layers.firstWhere((l) => l.id == a.id).timeline[0],
      isNotNull,
      reason: 'the block never left frame 0',
    );
  });
}
