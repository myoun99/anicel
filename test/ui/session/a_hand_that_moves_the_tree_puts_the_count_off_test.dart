import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show StandingDemand;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/playback_cache_budget.dart';

import '../../helpers/draw_on_current_frame.dart' show inkCel;

/// 🗣️F-620-Q3 = 2 (유저 2026-11-19 「끄는 동안은 세지 않는다 — 띠는 그
/// 컷 전체를 「준비 안 됨」으로」): while a hand moves what the frames are
/// made of, the cut it is in stands not ready and nothing is counted; it
/// is counted once the hand lets go. A hand whose tree stands — a scrub, a
/// stroke — counts as ever.
///
/// 🗣️F-620-Q4 = 1 (유저 2026-11-19 「카메라는 초록 그대로」): and only where
/// the FRAMES moved — a camera dragged moves the tree and no frame's
/// picture, and its bar is the frames as they stand, whenever it is asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
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

  Cut other(EditorSessionManager s) => s.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == const CutId('other'));

  /// The open cut's camera moved [by] at frame 0, in flight — shown, not
  /// written (`LaneEditPreview.camera`).
  void cameraDragged(EditorSessionManager s, int by) =>
      s.laneVerbs.previewLaneValueAt(
        const LayerId('open-cam'),
        'position',
        0,
        '$by, $by',
        frameIsGlobal: false,
        scaleLinked: true,
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

  test('a scrub and a stroke under a hand count as ever, and it lets go '
      'owing nothing', () {
    final s = session();
    final budget = s.playbackRig.playbackCache;
    final before = budget.playbackReadyRuns(0, 24);
    var heard = 0;
    budget.readinessMoved.addListener(() => heard += 1);

    s.playbackRig.prerenderScheduler.beginInputHold();
    s.selectFrameIndex(5);
    expect(budget.playbackReadyRuns(0, 24), before, reason: 'a scrub');

    inkCel(
      s,
      s.brushFrameKeyForCut(
        s.requireActiveCut,
        const LayerId('open-layer'),
        const FrameId('open-frame'),
      ),
      canvasSize: canvasSize,
      at: CanvasPoint(x: 1, y: 1),
      size: 2,
    );
    final stroked = budget.playbackReadyRuns(0, 24);
    heard = 0;
    s.playbackRig.prerenderScheduler.endInputHold();

    expect(heard, 0, reason: 'a stroke was counted, not put off');
    expect(budget.playbackReadyRuns(0, 24), stroked);
  });

  test('🚨a hand that moves the frames leaves its cut not ready, counts '
      'nothing under it, and the cut is counted once it lets go', () {
    final s = session();
    final budget = s.playbackRig.playbackCache;
    final open = s.activeCutOrNull!;
    expect(open.id, const CutId('open'), reason: 'the premise');
    final before = budget.playbackReadyRuns(0, 24);
    final otherBefore = budget.playbackReadyRunsForCut(
      other(s),
      0,
      24,
      paintPaper: false,
    );
    expect(before, isNotEmpty, reason: 'the premise: frames of nothing');

    s.playbackRig.prerenderScheduler.beginInputHold();
    // The paper's window, its wheel turning: every frame's page.
    s.projectSettings.showPaper(const ProjectBackground.color(0xFF336699));

    expect(budget.playbackReadyRuns(0, 24), isEmpty);
    expect(
      budget.playbackReadyRunsForCut(open, 0, 24, paintPaper: false),
      isEmpty,
      reason: 'the conte\'s bar: the cut the hand is in',
    );
    expect(
      budget.playbackReadyRunsForCut(other(s), 0, 24, paintPaper: false),
      otherBefore,
      reason: 'another cut of the conte is counted as ever',
    );

    var heard = 0;
    budget.readinessMoved.addListener(() => heard += 1);
    s.playbackRig.prerenderScheduler.endInputHold();

    expect(heard, 1, reason: 'counted once, as the hand lets go');
    s.projectSettings.writeShownPlanes();
    expect(budget.playbackReadyRuns(0, 24), before);
  });

  test('🚨a camera dragged moves no frame: its bar is the frames as they '
      'stand whenever it is asked, and the hand lets go owing nothing', () {
    final s = session();
    final budget = s.playbackRig.playbackCache;
    final open = s.activeCutOrNull!;
    final before = budget.playbackReadyRuns(0, 24);
    final conteBefore = budget.playbackReadyRunsForCut(
      open,
      0,
      24,
      paintPaper: false,
    );
    expect(before, isNotEmpty, reason: 'the premise: frames of nothing');
    var heard = 0;
    budget.readinessMoved.addListener(() => heard += 1);

    s.playbackRig.prerenderScheduler.beginInputHold();
    cameraDragged(s, 10);
    expect(s.dragPreview.value, isNotNull, reason: 'the premise: in flight');
    expect(budget.playbackReadyRuns(0, 24), before, reason: 'a first step');
    cameraDragged(s, 20);
    expect(
      budget.playbackReadyRunsForCut(open, 0, 24, paintPaper: false),
      conteBefore,
      reason: 'the conte\'s bar, asked at another step',
    );
    expect(budget.playbackReadyRuns(0, 24), before, reason: 'asked again');

    s.laneVerbs.endLaneEditPreview();
    s.playbackRig.prerenderScheduler.endInputHold();

    expect(heard, 0, reason: 'nothing was put off');
    expect(budget.playbackReadyRuns(0, 24), before);
  });

  test('the frame a hand notes is the one the warmer stands on — the '
      'playhead\'s — or its cut\'s first where it stands on none of it', () {
    StandingDemand around(int frame) => StandingDemand(
      cutId: const CutId('open'),
      frameCount: 24,
      around: frame,
      resolveCut: (id) => id == const CutId('open') ? cutOf('open') : null,
    );

    expect(
      PlaybackCacheBudget.frameStoodOn(around(12), const CutId('open')),
      12,
    );
    expect(
      PlaybackCacheBudget.frameStoodOn(around(12), const CutId('other')),
      0,
    );
    expect(PlaybackCacheBudget.frameStoodOn(null, const CutId('open')), 0);
  });

  test('a press a project closed under lets go of its warmer after, and '
      'nothing is told', () {
    final s = session();
    final warmer = s.playbackRig.prerenderScheduler;
    warmer.beginInputHold();
    s.dispose();

    expect(warmer.endInputHold, returnsNormally);
  });
}
