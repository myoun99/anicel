import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/run_edge_fixtures.dart';

/// F-21 and F-13 — what the FLIP verb does.
///
/// F-21 (유저 2026-08-24): 「1번인덱스에 홀드인 블록하나 있을때 중간인덱스,
/// 5번인덱스인 상태에서 왼쪽 플립하면 인덱스 이동안함. 해당 상황같은
/// 이동할수없는 상황에서는 우선 1번인덱스로 이동하도록」.
///
/// F-13 (같은 날): 「선택범위로 선택하고 취소되는 행동 늘리고싶음 … 플립하면
/// 선택범위 취소되도록. 다만 룰러 스크럽시 취소안되는건 그대로 남김」.
void main() {
  const trackId = TrackId('flip-track');
  const layerId = LayerId('flip-layer');

  /// One drawing at frame 0 with an END-side HOLD, so its ghosts fill the
  /// cut: the whole row is ONE flip column, which is the shape that made
  /// the leftward flip do nothing at all.
  Project heldProject() => Project(
    id: const ProjectId('flip-project'),
    name: 'Flip',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: trackId,
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: '1',
            duration: 12,
            canvasSize: const CanvasSize(width: 64, height: 64),
            layers: [
              // The ghosts are DERIVED, never hand-written: `rederiveRunBehaviors`
              // is what the repository runs, and a hand-rolled ghost whose
              // stamp does not say hold is not a hold — it is twelve
              // one-frame columns wearing a hold's clothes.
              rederiveRunBehaviors(
                Layer(
                  id: layerId,
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('cel'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: const {
                    0: TimelineExposure.drawing(
                      FrameId('cel'),
                      length: 1,
                      endEdge: holdMark,
                    ),
                  },
                ),
                cutFrameCount: 12,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager sessionFor(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  group('F-21: a flip with nowhere to go lands on the first frame', () {
    test('mid-hold, leftward: it used to do nothing at all', () {
      final session = sessionFor(heldProject());
      session.selectLayer(layerId);
      session.selectFrameIndex(5);
      expect(session.currentFrameIndex, 5, reason: 'fixture premise');

      session.frameVerbs.flipRow(forward: false);

      expect(
        session.currentFrameIndex,
        0,
        reason: 'the hold starts at 0, so the whole row is one column and '
            'the step asks for frame -1. Falling to the first frame is a '
            'move; refusing is not',
      );
    });

    test('and standing ON the first frame it stays there — nothing to do is '
        'not the same as somewhere to go', () {
      final session = sessionFor(heldProject());
      session.selectLayer(layerId);
      session.selectFrameIndex(0);

      session.frameVerbs.flipRow(forward: false);

      expect(session.currentFrameIndex, 0);
    });
  });

  group('F-13: the flip clears the selection, the scrub does not', () {
    test('a flip drops the frame range', () {
      final session = sessionFor(createDefaultProject());
      final layer = session.layers.first;
      session.selectLayer(layer.id);
      session.updateFrameRangeSelectionDrag(
        layerId: layer.id,
        anchorIndex: 0,
        headIndex: 2,
      );
      expect(
        session.frameRangeSelection.value,
        isNotNull,
        reason: 'fixture premise: something is selected',
      );

      session.frameVerbs.flipRow(forward: true);

      expect(session.frameRangeSelection.value, isNull);
    });

    test('a plain seek — the ruler scrub path — keeps it', () {
      final session = sessionFor(createDefaultProject());
      final layer = session.layers.first;
      session.selectLayer(layer.id);
      session.updateFrameRangeSelectionDrag(
        layerId: layer.id,
        anchorIndex: 0,
        headIndex: 2,
      );

      session.selectFrameIndex(5);

      expect(
        session.frameRangeSelection.value,
        isNotNull,
        reason: '「룰러쪽 조작은 지금처럼 그대로 취소안되도록」 — the clear '
            'belongs to the FLIP verb, not to seeking',
      );
    });
  });
}
