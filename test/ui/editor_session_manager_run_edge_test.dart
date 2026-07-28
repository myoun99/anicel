import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// UI-R9 #10: the session's run-edge property API — one-undo commits,
/// selection-scoped repeat patterns, None clears.
void main() {
  (EditorSessionManager, LayerId) sessionWithBlock() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    return (s, s.activeLayer!.id);
  }

  Layer layerOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((layer) => layer.id == id);

  test('end HOLD fills ghosts to the cut end as ONE undo step', () {
    final (s, layerId) = sessionWithBlock();
    final cutEnd = s.requireActiveCut.duration;

    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );

    var layer = layerOf(s, layerId);
    expect(layer.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
    expect(layer.timeline[1]!.ghost, isTrue);
    expect(layer.timeline[1]!.length, cutEnd - 1);

    s.undo();
    layer = layerOf(s, layerId);
    expect(layer.runBehaviors, isEmpty);
    expect(layer.timeline.values.any((entry) => entry.ghost), isFalse);

    s.redo();
    layer = layerOf(s, layerId);
    expect(layer.runBehaviors, hasLength(1));
    expect(layer.timeline[1]!.ghost, isTrue);
  });

  test('None clears the edge (behaviors AND ghosts)', () {
    final (s, layerId) = sessionWithBlock();
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    expect(layerOf(s, layerId).timeline[1]!.ghost, isTrue);

    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: null,
    );

    final layer = layerOf(s, layerId);
    expect(layer.runBehaviors, isEmpty);
    expect(layer.timeline.values.any((entry) => entry.ghost), isFalse);
  });

  test('scopeToSelection FALSE keeps the whole run even with a live '
      'selection — the flyout\'s explicit "Repeat" entry (UI-R19 #2)', () {
    final (s, layerId) = sessionWithBlock();
    s.selectFrameIndex(1);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 1,
      headIndex: 2,
    );

    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
      scopeToSelection: false,
    );

    final layer = layerOf(s, layerId);
    expect(
      layer.runBehaviors.single.patternAnchorFrameId,
      isNull,
      reason: 'the whole run cycles — the selection is deliberately ignored',
    );
    // The ghost tail cycles ALL three frames.
    expect(layer.timeline[3]!.frameId, layer.timeline[0]!.frameId);
  });

  test('canScopeRepeatToSelection mirrors the pattern rules (UI-R19 #2: '
      'the "Repeat selection" flyout entry\'s gate)', () {
    final (s, layerId) = sessionWithBlock();
    s.selectFrameIndex(1);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();

    // No selection: nothing to scope.
    expect(
      s.canScopeRepeatToSelection(
        layerId: layerId,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
      ),
      isFalse,
    );

    // Tail selection [1,3): scopes the END edge, not the START one.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(
      s.canScopeRepeatToSelection(
        layerId: layerId,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
      ),
      isTrue,
    );
    expect(
      s.canScopeRepeatToSelection(
        layerId: layerId,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.start,
      ),
      isFalse,
    );

    // A whole-run selection scopes nothing (it IS the run).
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(
      s.canScopeRepeatToSelection(
        layerId: layerId,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
      ),
      isFalse,
    );
  });

  test('a selection covering the run tail scopes the repeat pattern', () {
    final (s, layerId) = sessionWithBlock();
    s.selectFrameIndex(1);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    final blocks = layerOf(s, layerId).timeline;
    final secondFrameId = blocks[1]!.frameId;

    // Select the LAST TWO blocks [1,3) — the pattern for the end repeat.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 1,
      headIndex: 2,
    );
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );

    final layer = layerOf(s, layerId);
    expect(
      layer.runBehaviors.single.patternAnchorFrameId,
      secondFrameId,
      reason: 'the selection start block anchors the pattern',
    );
    // Ghosts cycle the two selected frames, not all three.
    expect(layer.timeline[3]!.frameId, blocks[1]!.frameId);
    expect(layer.timeline[4]!.frameId, blocks[2]!.frameId);
    expect(layer.timeline[5]!.frameId, blocks[1]!.frameId);
  });

  test('the end behavior anchors to the run LAST block: splitting the run '
      'keeps the repeat with the edge fragment (UI-R10 #4)', () {
    final (s, layerId) = sessionWithBlock(); // block 1 at 0
    s.selectFrameIndex(1);
    s.createDrawingAtCurrentFrame(); // block 2 at 1
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame(); // block 3 at 2 — run {0,1,2}
    final lastBlockFrameId = layerOf(s, layerId).timeline[2]!.frameId;

    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    expect(
      layerOf(s, layerId).runBehaviors.single.anchorFrameId,
      lastBlockFrameId,
      reason: 'the end edge anchors to the LAST block, not the run start',
    );

    // Move blocks {1,2} away (range move): the repeat follows THEM.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 4);
    s.endFrameRangeMoveDrag();

    final layer = layerOf(s, layerId);
    // Fragment {5,6}: ghosts refill after ITS end (7..), and the lone
    // block at 0 grows nothing.
    expect(layer.timeline[7]!.ghost, isTrue);
    expect(layer.timeline.containsKey(1), isFalse);
  });

  test('re-setting the same edge replaces the previous behavior', () {
    final (s, layerId) = sessionWithBlock();
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );

    final layer = layerOf(s, layerId);
    expect(layer.runBehaviors, hasLength(1));
    expect(layer.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
  });

  test('start-side hold back-fills to frame 0', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;

    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 4,
      side: TimelineRunEdgeSide.start,
      mode: TimelineRunEdgeMode.hold,
    );

    final layer = s.layers.firstWhere((layer) => layer.id == layerId);
    expect(layer.timeline[0]!.ghost, isTrue);
    expect(layer.timeline[0]!.length, 4);
    expect(layer.timeline[4]!.ghost, isFalse);
  });

  test('a cut duration change refills the hold tail through the '
      'repository choke point (storyboard end-trim)', () {
    final (s, layerId) = sessionWithBlock();
    final cutEnd = s.requireActiveCut.duration;
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );
    expect(layerOf(s, layerId).timeline[1]!.length, cutEnd - 1);

    expect(
      s.beginCutEdgeDrag(
        cutId: s.requireActiveCut.id,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.updateCutEdgeDrag(6);
    s.endCutEdgeDrag();

    expect(s.requireActiveCut.duration, cutEnd + 6);
    expect(layerOf(s, layerId).timeline[1]!.length, cutEnd + 5);

    // Undo restores the old duration AND the old tail.
    s.undo();
    expect(layerOf(s, layerId).timeline[1]!.length, cutEnd - 1);
  });
}
