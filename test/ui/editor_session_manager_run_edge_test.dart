import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/edge_drag.dart';

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

  /// The END-side property of the run starting at [start].
  TimelineRunEdgeProperty? endOf(Layer layer, [int start = 0]) =>
      runEdgeBehaviorAt(layer, start, TimelineRunEdgeSide.end);

  /// Every property the row's blocks carry, one per (block, side).
  List<TimelineRunEdgeMode> carriedModes(Layer layer) => [
    for (final entry in layer.timeline.values)
      for (final side in TimelineRunEdgeSide.values) ?entry.edgeMark(side).mode,
  ];

  test('end HOLD fills ghosts to the cut end as ONE undo step', () {
    final (s, layerId) = sessionWithBlock();
    final cutEnd = s.requireActiveCut.duration;

    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );

    var layer = layerOf(s, layerId);
    expect(endOf(layer)?.mode, TimelineRunEdgeMode.hold);
    expect(layer.timeline[1]!.ghost, isTrue);
    expect(layer.timeline[1]!.length, cutEnd - 1);

    s.undo();
    layer = layerOf(s, layerId);
    expect(endOf(layer), isNull);
    expect(layer.timeline.values.any((entry) => entry.ghost), isFalse);

    s.redo();
    layer = layerOf(s, layerId);
    expect(endOf(layer)?.mode, TimelineRunEdgeMode.hold);
    expect(layer.timeline[1]!.ghost, isTrue);
  });

  test('None clears the edge (behaviors AND ghosts)', () {
    final (s, layerId) = sessionWithBlock();
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    expect(layerOf(s, layerId).timeline[1]!.ghost, isTrue);

    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: null,
    );

    final layer = layerOf(s, layerId);
    expect(endOf(layer), isNull);
    expect(carriedModes(layer), isEmpty, reason: 'None leaves no mark behind');
    expect(layer.timeline.values.any((entry) => entry.ghost), isFalse);
  });

  test('None clears a carrier that is no longer its run\'s edge block — a '
      'property set before the run grew', () {
    final (s, layerId) = sessionWithBlock(); // block at 0
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );
    s.selectFrameIndex(1);
    s.createDrawingAtCurrentFrame(); // glued on past the carrier
    expect(
      layerOf(s, layerId).timeline[0]!.endEdge.mode,
      TimelineRunEdgeMode.hold,
      reason: 'LIVENESS — the carrier sits inside the run now',
    );
    expect(endOf(layerOf(s, layerId))?.mode, TimelineRunEdgeMode.hold);

    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 1,
      side: TimelineRunEdgeSide.end,
      mode: null,
    );

    final layer = layerOf(s, layerId);
    expect(carriedModes(layer), isEmpty, reason: 'every block gives it up');
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

    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
      scopeToSelection: false,
    );

    final layer = layerOf(s, layerId);
    expect(endOf(layer)?.mode, TimelineRunEdgeMode.repeat);
    expect(
      endOf(layer)!.patternBlockStart,
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

    // Select the LAST TWO blocks [1,3) — the pattern for the end repeat.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 1,
      headIndex: 2,
    );
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );

    final layer = layerOf(s, layerId);
    expect(
      endOf(layer)?.patternBlockStart,
      1,
      reason: 'the selection start block bounds the pattern',
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

    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    expect(
      layerOf(s, layerId).timeline[2]!.endEdge.mode,
      TimelineRunEdgeMode.repeat,
      reason: 'the end edge sits on the LAST block, not the run start',
    );
    expect(layerOf(s, layerId).timeline[0]!.endEdge.isNone, isTrue);

    // Move blocks {1,2} away (range move): the repeat follows THEM.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 4);
    s.rangeMove.endFrameRangeMoveDrag();

    final layer = layerOf(s, layerId);
    // Fragment {5,6}: ghosts refill after ITS end (7..), and the lone
    // block at 0 grows nothing.
    expect(layer.timeline[7]!.ghost, isTrue);
    expect(layer.timeline.containsKey(1), isFalse);
  });

  test('re-setting the same edge replaces the previous behavior', () {
    final (s, layerId) = sessionWithBlock();
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );

    final layer = layerOf(s, layerId);
    expect(carriedModes(layer), [TimelineRunEdgeMode.hold]);
    expect(endOf(layer)?.mode, TimelineRunEdgeMode.hold);
  });

  test('start-side hold back-fills to frame 0', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;

    s.rangeMove.setRunEdgeBehavior(
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
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );
    expect(layerOf(s, layerId).timeline[1]!.length, cutEnd - 1);

    expect(
      edgeDragOf(s).beginCutEdgeDrag(
        cutId: s.requireActiveCut.id,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    edgeDragOf(s).updateCutEdgeDrag(6);
    edgeDragOf(s).endCutEdgeDrag();

    expect(s.requireActiveCut.duration, cutEnd + 6);
    expect(layerOf(s, layerId).timeline[1]!.length, cutEnd + 5);

    // Undo restores the old duration AND the old tail.
    s.undo();
    expect(layerOf(s, layerId).timeline[1]!.length, cutEnd - 1);
  });

  test('a setting replaces ONLY its own (run, side) — the other edge and '
      'the other run keep theirs', () {
    // Two runs, four edges. The case above re-sets one edge of one run, so
    // a replacement that took out the opposite side, or another run's
    // behaviour, looked exactly the same (the run-edge split's surviving
    // mutants, 2026-09-04).
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final layerId = s.activeLayer!.id;
    for (final frame in [0, 4]) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
    }
    for (final start in [0, 4]) {
      for (final side in TimelineRunEdgeSide.values) {
        s.rangeMove.setRunEdgeBehavior(
          layerId: layerId,
          blockStartIndex: start,
          side: side,
          mode: TimelineRunEdgeMode.hold,
        );
      }
    }
    expect(
      carriedModes(layerOf(s, layerId)),
      hasLength(4),
      reason: 'engagement first: two runs, both edges each',
    );

    // Re-set ONE of them. The other three are untouched.
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    final after = carriedModes(layerOf(s, layerId));
    expect(
      after,
      hasLength(4),
      reason:
          'a setting replaces one behaviour, it does not clear others — '
          'ignoring the SIDE takes out the opposite edge, and ignoring the '
          'RUN takes out the other run',
    );
    expect(
      after.where((mode) => mode == TimelineRunEdgeMode.repeat),
      hasLength(1),
      reason: 'exactly the one that was re-set',
    );
    expect(
      after.where((mode) => mode == TimelineRunEdgeMode.hold),
      hasLength(3),
    );
  });

  test('the START side scopes its repeat pattern to the LAST block the '
      'selection still covers (UI-R19 #2, the other half)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame(); // block at 3
    final layerId = s.activeLayer!.id;
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame(); // block at 4
    s.selectFrameIndex(5);
    s.createDrawingAtCurrentFrame(); // block at 5 — run {3,4,5}
    final blocks = layerOf(s, layerId).timeline;

    // Select [3,5): covers the run's FIRST block and ends inside the run.
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 3,
      headIndex: 4,
    );
    expect(
      s.canScopeRepeatToSelection(
        layerId: layerId,
        blockStartIndex: 3,
        side: TimelineRunEdgeSide.start,
      ),
      isTrue,
    );
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 3,
      side: TimelineRunEdgeSide.start,
      mode: TimelineRunEdgeMode.repeat,
    );

    final layer = layerOf(s, layerId);
    expect(
      runEdgeBehaviorAt(
        layer,
        3,
        TimelineRunEdgeSide.start,
      )?.patternBlockStart,
      4,
      reason: 'the pattern ends at the last block inside the selection',
    );
    // Ghosts back-fill by cycling the two selected frames, not all three.
    expect(layer.timeline[2]!.frameId, blocks[4]!.frameId);
    expect(layer.timeline[1]!.frameId, blocks[3]!.frameId);
  });
}

/// The collaborator that owns the laws above, under its OWN name.
///
/// 🚨`tool/mutation_run.dart` picks the tests that will witness a mutation by
/// asking which tests IMPORT the file. Round 8 carved ~50 collaborators out of
/// `EditorSessionManager` and every pin still arrived through the session, so
/// 63 of the 71 files under `lib/src/ui/session/` reported UNNAMED and the
/// campaign skipped exactly the code that round wrote. ⛔Widening the runner to
/// transitive reachability was tried and reverted (one small file drew 390
/// namers); a collaborator that holds a law gets a test that names it instead.
EdgeDragVerbs edgeDragOf(EditorSessionManager session) => session.edgeDrag;
