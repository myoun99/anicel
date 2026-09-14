// A REPEAT SCOPED TO THE SELECTION TAKES ITS PATTERN FROM THE SIDE THE
// EDGE IS ON — AND ONLY WHEN THE SELECTION STARTS OR ENDS INSIDE THE RUN.
//
// Two survivors of the mutation campaign (2026-09-04, the pattern-anchor
// split): the end side scoped a selection that started AT the run's start
// (the whole run is the pattern then — no anchor), and the start side
// anchored on the FIRST block under the selection instead of the LAST.
// The run-edge tests only ever selected a tail; these pins select the
// whole run and a head.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  Layer layerOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((layer) => layer.id == id);

  /// A session with one drawing row carrying single-frame blocks at [at].
  (EditorSessionManager, LayerId) sessionWithBlocksAt(List<int> at) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final layerId = s.activeLayer!.id;
    for (final frame in at) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
    }
    return (s, layerId);
  }

  test('end side: a selection starting AT the run start scopes nothing — '
      'the whole run is the pattern', () {
    final (s, layerId) = sessionWithBlocksAt([0, 1, 2]);
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 0,
      headIndex: 2,
    );
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    final end = runEdgeBehaviorAt(
      layerOf(s, layerId),
      0,
      TimelineRunEdgeSide.end,
    );
    expect(end?.mode, TimelineRunEdgeMode.repeat);
    expect(
      end!.patternBlockStart,
      isNull,
      reason: 'the selection must START inside the run to scope the pattern',
    );
  });

  test('start side: the pattern runs from the run start to the LAST block '
      'ending by the selection end', () {
    final (s, layerId) = sessionWithBlocksAt([2, 3, 4]);
    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 2,
      headIndex: 3,
    );
    s.rangeMove.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 2,
      side: TimelineRunEdgeSide.start,
      mode: TimelineRunEdgeMode.repeat,
    );
    final start = runEdgeBehaviorAt(
      layerOf(s, layerId),
      2,
      TimelineRunEdgeSide.start,
    );
    expect(start?.mode, TimelineRunEdgeMode.repeat);
    expect(
      start!.patternBlockStart,
      3,
      reason: 'the last block the selection still covers bounds the pattern',
    );
  });
}
