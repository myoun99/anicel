import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/key_side.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts, StandingDemand;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/playback_cache_budget.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart' show effectLaneId;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformTrackWithScaleDragged;

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
///
/// 🗣️F-620-Q8 = 「비운다(지금 그대로)」 (유저 2026-11-20): but a frame a
/// name tag stands on is made of the camera — the tag is posed in the shot
/// (I-67-Q1) — and a camera dragged over it moves the frames as any hand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// [id]'s cut: a drawn row, [dressed] as a test asks, and a camera.
  Cut cutOf(String id, {Layer Function(Layer row)? dressed}) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: canvasSize,
    layers: [
      (dressed ?? (row) => row)(
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
      ),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  /// The open cut — its drawn row [dressed] — and another, the track's SE
  /// rows [seRows].
  EditorSessionManager session({
    Layer Function(Layer row)? dressed,
    List<Layer> seRows = const [],
  }) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'T',
          cuts: [cutOf('open', dressed: dressed), cutOf('other')],
          seLayers: seRows,
        ),
      ],
    ),
  );

  /// An SE row whose name tag stands over the open cut's frames — posed in
  /// the shot, so the camera moves it on the canvas (I-67-Q1).
  final aNameTag = Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [
      Frame(
        id: const FrameId('se-cel'),
        duration: 24,
        strokes: const [],
        seName: 'S',
      ),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('se-cel'), length: 24),
    },
  );

  Cut other(EditorSessionManager s) => s.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == const CutId('other'));

  /// The open cut's drawn row.
  const drawnRow = LayerId('open-layer');

  /// The one effect a row is dressed with ([dressedWith]).
  const anEffect = EffectId('open-fx');

  /// [row] with [kind]'s effect at its defaults ([anEffect]).
  Layer dressedWith(Layer row, EffectKind kind) => row.copyWith(
    effects: [LayerEffect.defaults(id: anEffect, kind: kind)],
  );

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

  /// What a lane's door shows in flight — the preview channel's.
  Object? onTheLanes(EditorSessionManager s) => s.dragPreview.value;

  /// Every door a value is shown through, not written — each family's, on
  /// the canvas and on the timeline — what it shows on, and how its hand
  /// lets go. 🗣️관제 11-19 22:4x: 「어느 값이든 그림이 바뀌면 비고」 — the
  /// band reads the frame the canvas shows, whatever moved it.
  final doors = <({
    String door,
    int watched,
    Layer Function(Layer row)? dressed,
    List<Layer> seRows,
    void Function(EditorSessionManager s) hand,
    Object? Function(EditorSessionManager s) shown,
    void Function(EditorSessionManager s) letGo,
  })>[
    (
      door: 'a lane\'s value — the row\'s position',
      watched: 0,
      dressed: null,
      seRows: const [],
      hand: (s) => s.laneVerbs.previewLaneValueAt(
        drawnRow,
        'position',
        0,
        '3, 3',
        frameIsGlobal: false,
        scaleLinked: true,
      ),
      shown: onTheLanes,
      letGo: (s) => s.laneVerbs.endLaneEditPreview(),
    ),
    (
      door: 'the canvas\'s box — the row\'s transform',
      watched: 0,
      dressed: null,
      seRows: const [],
      hand: (s) => s.laneVerbs.previewLayerTransformAtPlayhead(
        drawnRow,
        (track, f) => transformTrackWithScaleDragged(
          track,
          frameIndex: f,
          scale: CanvasPoint(x: 2, y: 2),
        ),
      ),
      shown: onTheLanes,
      letGo: (s) => s.laneVerbs.endLaneEditPreview(),
    ),
    (
      door: 'a graph\'s handle — a key\'s sides, between two keys',
      watched: 4,
      dressed: (row) => row.copyWith(
        transformTrack: TransformTrack(
          keyframes: {
            0: TransformPose(center: CanvasPoint(x: 4, y: 4)),
            8: TransformPose(
              center: CanvasPoint(x: 4, y: 4),
              rotationDegrees: 40,
            ),
          },
        ),
      ),
      seRows: const [],
      hand: (s) => s.laneVerbs.previewLaneKeySidesAt(
        const LaneRowAddress(drawnRow, 'rotation'),
        0,
        const KeySidesEdit(
          outgoing: KeySideEdit(side: EaseSide(influence: 0.5, speed: 2)),
        ),
        frameIsGlobal: false,
      ),
      shown: onTheLanes,
      letGo: (s) => s.laneVerbs.endLaneEditPreview(),
    ),
    (
      door: 'an effect\'s lane value',
      watched: 0,
      dressed: (row) => dressedWith(row, EffectKind.brightnessContrast),
      seRows: const [],
      hand: (s) => s.laneVerbs.previewLaneValueAt(
        drawnRow,
        effectLaneId(anEffect, 'brightness'),
        0,
        '40',
        frameIsGlobal: false,
        scaleLinked: false,
      ),
      shown: onTheLanes,
      letGo: (s) => s.laneVerbs.endLaneEditPreview(),
    ),
    (
      door: 'an effect\'s box on the canvas — a cel number\'s',
      watched: 0,
      dressed: (row) => dressedWith(row, EffectKind.celNumber),
      seRows: const [],
      hand: (s) => s.laneVerbs.previewEffectKeysAtPlayhead(
        drawnRow,
        effectLaneId(anEffect, 'scale'),
        (track, f) => transformTrackWithScaleDragged(
          track,
          frameIndex: f,
          scale: CanvasPoint(x: 2, y: 2),
        ),
      ),
      shown: onTheLanes,
      letGo: (s) => s.laneVerbs.endLaneEditPreview(),
    ),
    (
      door: 'a row\'s opacity slider',
      watched: 0,
      dressed: null,
      seRows: const [],
      hand: (s) => s.opacityVerbs.previewLayerOpacity(drawnRow, 0.5),
      shown: (s) => s.opacityVerbs.dragPreview.value,
      letGo: (s) => s.opacityVerbs.commitLayerOpacity(drawnRow, 1),
    ),
    (
      door:
          'the open cut\'s camera, a name tag standing on the frame — '
          'posed in the shot, the tag moves on the canvas (🗣️F-620-Q8 = '
          '「비운다(지금 그대로)」)',
      watched: 0,
      dressed: null,
      seRows: [aNameTag],
      hand: (s) => cameraDragged(s, 10),
      shown: onTheLanes,
      letGo: (s) => s.laneVerbs.endLaneEditPreview(),
    ),
  ];

  for (final (:door, :watched, :dressed, :seRows, :hand, :shown, :letGo)
      in doors) {
    testWidgets('🚨a value shown, not written, moves the frames all the same '
        '— $door: its cut stands not ready, counted once the hand lets go '
        '(검증/서피스 21:36: the box of a cel number, a lane\'s colour wheel)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = session(dressed: dressed, seRows: seRows);
        addTearDown(s.dispose);
        final open = s.activeCutOrNull!;
        final budget = s.playbackRig.playbackCache;
        // A row with nothing drawn lies in no frame's picture: inked.
        inkCel(
          s,
          s.brushFrameKeyForCut(open, drawnRow, const FrameId('open-frame')),
          canvasSize: canvasSize,
          at: CanvasPoint(x: 1, y: 1),
          size: 2,
        );
        await s.playbackRig.framePictures.make((
          cut: open,
          frameIndex: watched,
          paintPaper: true,
          ghosts: FrameGhosts.none,
        ), shouldAbort: () => false);
        final before = budget.playbackReadyRuns(watched, watched + 1);
        expect(before, isNotEmpty, reason: '⛔premise: the frame made');
        var heard = 0;
        budget.readinessMoved.addListener(() => heard += 1);

        s.playbackRig.prerenderScheduler.beginInputHold();
        hand(s);
        expect(shown(s), isNotNull, reason: '⛔premise: shown');

        expect(budget.playbackReadyRuns(watched, watched + 1), isEmpty);

        letGo(s);
        s.playbackRig.prerenderScheduler.endInputHold();

        expect(heard, 1, reason: 'counted once, as the hand lets go');
        expect(
          budget.playbackReadyRuns(watched, watched + 1),
          before,
          reason: 'nothing written: the frame made is the frame shown again',
        );
      });
    });
  }

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

  test('🚨the camera\'s opacity slider dims the camera view and moves no '
      'frame: its bar is the frames as they stand (F-363)', () {
    final s = session();
    final budget = s.playbackRig.playbackCache;
    final before = budget.playbackReadyRuns(0, 24);
    expect(before, isNotEmpty, reason: 'the premise: frames of nothing');
    var heard = 0;
    budget.readinessMoved.addListener(() => heard += 1);

    s.playbackRig.prerenderScheduler.beginInputHold();
    s.opacityVerbs.previewLayerOpacity(const LayerId('open-cam'), 0.5);
    expect(
      s.opacityVerbs.dragPreview.value,
      isNotNull,
      reason: 'the premise: in flight',
    );
    expect(budget.playbackReadyRuns(0, 24), before);

    s.opacityVerbs.commitLayerOpacity(const LayerId('open-cam'), 1);
    s.playbackRig.prerenderScheduler.endInputHold();

    expect(heard, 0, reason: 'nothing was put off');
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
