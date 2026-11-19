import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// 🗣️F-620-Q3 = 2 (유저 2026-11-19 「끄는 동안은 세지 않는다 — 띠는 그
/// 컷 전체를 「준비 안 됨」으로」): while a hand moves what the frames are
/// made of, the cut it is in stands not ready and nothing is counted; it
/// is counted once the hand lets go. A hand whose tree stands — a scrub, a
/// stroke — counts as ever.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Cut cutOf(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: LayerId('$id-layer'),
        name: 'A',
        frames: [
          Frame(id: FrameId('$id-frame'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$id-frame'), length: 24),
        },
      ),
    ],
  );

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'T',
          cuts: [cutOf('open'), cutOf('other')],
        ),
      ],
    ),
  );

  test('a hand whose tree stands counts as ever, and lets go owing '
      'nothing', () {
    final s = session();
    final budget = s.playbackRig.playbackCache;
    final before = budget.playbackReadyRuns(0, 24);
    expect(before, isNotEmpty, reason: 'the premise: frames of nothing');

    s.playbackRig.prerenderScheduler.beginInputHold();
    expect(budget.playbackReadyRuns(0, 24), before);

    var heard = 0;
    budget.readinessMoved.addListener(() => heard += 1);
    s.playbackRig.prerenderScheduler.endInputHold();
    expect(heard, 0);
  });

  test('🚨a hand that moves the tree leaves its cut not ready, counts '
      'nothing under it, and the cut is counted once it lets go', () {
    final s = session();
    final budget = s.playbackRig.playbackCache;
    final open = s.activeCutOrNull!;
    expect(open.id, const CutId('open'), reason: 'the premise');
    final other = s.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .firstWhere((cut) => cut.id == const CutId('other'));
    final before = budget.playbackReadyRuns(0, 24);
    final otherBefore = budget.playbackReadyRunsForCut(
      other,
      0,
      24,
      paintPaper: false,
    );
    expect(before, isNotEmpty, reason: 'the premise: frames of nothing');

    s.playbackRig.prerenderScheduler.beginInputHold();
    s.dragPreview.value = const MovieEndDragPreview(trailingFrames: 3);

    expect(budget.playbackReadyRuns(0, 24), isEmpty);
    expect(
      budget.playbackReadyRunsForCut(open, 0, 24, paintPaper: false),
      isEmpty,
      reason: 'the conte\'s bar: the cut the hand is in',
    );
    expect(
      budget.playbackReadyRunsForCut(other, 0, 24, paintPaper: false),
      otherBefore,
      reason: 'another cut of the conte is counted as ever',
    );

    var heard = 0;
    budget.readinessMoved.addListener(() => heard += 1);
    s.dragPreview.value = null;
    s.playbackRig.prerenderScheduler.endInputHold();

    expect(heard, 1, reason: 'counted once, as the hand lets go');
    expect(budget.playbackReadyRuns(0, 24), before);
  });
}
