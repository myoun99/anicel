import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/storyboard_layer_policy.dart'
    show projectedLayerInHand;
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart'
    show seekStoryboardCutFrame;
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️I-73 ④ (유저 2026-10-08): 「카메라 행 범위는 키표시/이동/레인 등 모든거
/// 콘티패널에서 가능」 — and the drawn proposal's table: 「카메라 — 서면 키 ·
/// 플립 · 삭제 · 코마 = 타임라인의 카메라 행과 같음 · 타임라인의 자리 = 카메라
/// 행」.
///
/// Standing on the storyboard's camera row stands the timeline on the camera
/// row of the cut the session stands in, and the frame buttons are that
/// row's: ＋ keys the cell, Delete takes its key, Edit opens it, the flip
/// walks a frame at a time — every button answering as the timeline's camera
/// row answers on the same cell. Where the row holds no camera — a gap —
/// they are dark, and no other row is touched (↩️and once the timeline had
/// picked another layer, until I-126 stood the storyboard where it stands).
///
/// Cuts a [0, 24) with camera keys 0 and 12, b [24, 48) with 2 and 6, four
/// frames of gap, c [52, 64). Each cut's cel row holds one block of twelve.
void main() {
  const trackId = TrackId('t');
  const a = CutId('a');
  const b = CutId('b');
  final cameraRow = LayerRowAddress(trackCameraRowId(trackId));

  Cut cutOf(String id, int duration, List<int> keys, {int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: CutCamera(
      keyframes: {
        for (final frame in keys)
          frame: CameraPose(center: CanvasPoint(x: 320.0 + frame, y: 180)),
      },
    ),
    layers: [
      Layer(
        id: LayerId('$id-cel'),
        name: 'A',
        frames: [
          Frame(id: FrameId('$id-1'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$id-1'), length: 12),
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

  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: trackId,
            name: 'V',
            cuts: [
              cutOf('a', 24, [0, 12]),
              cutOf('b', 24, [2, 6]),
              cutOf('c', 12, const [], gap: 4),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectCut(a);
    session.selectLayer(const LayerId('a-cel'));
    return session;
  }

  /// The storyboard, stood on its camera row at [globalFrame].
  EditorSessionManager onTheCameraRow(int globalFrame) => open()
    ..standOnRow(
      cameraRow,
      panel: WorkingPanel.storyboard,
      globalFrameIndex: globalFrame,
    );

  /// The TIMELINE, stood on [cutId]'s camera row at its own [frame] — the
  /// row whose answers the storyboard's camera row borrows.
  EditorSessionManager onTheTimelinesCameraRow(CutId cutId, int frame) =>
      open()
        ..selectCut(cutId)
        ..standOnRow(LayerRowAddress(LayerId('${cutId.value}-cam')))
        ..selectFrameIndex(frame);

  List<int> keysOf(EditorSessionManager session, CutId cutId) => [
    ...session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .singleWhere((cut) => cut.id == cutId)
        .camera
        .keyframes
        .keys,
  ];

  /// Every button the row borrows, as [panel] answers it.
  Map<String, Object?> answersOf(
    ToolbarPanelContext panel,
    EditorSessionManager session,
  ) => {
    'create': panel.canCreateInstance,
    'edit': panel.canEditInstance,
    'delete': panel.deleteSubject,
    'comma': panel.canSetComma,
    'blank': panel.canBlankExposure,
    'mark': panel.canToggleMark,
    'mark every': panel.canMarkEvery,
    'cut': panel.canCutRun,
    'copy': panel.canCopyFrame,
    'paste': panel.canPasteIndependentFrame,
    'paste linked': panel.canPasteLinkedFrame,
    'row span': panel.canSelectRowSpan,
    'unlink': panel.canUnlink,
    'auto-name': panel.canAutoName,
    'push': session.blockShift.canPushBlocks(
      currentRow: panel.shiftCurrentRow,
    ),
    'pull': session.blockShift.canPullBlocks(
      currentRow: panel.shiftCurrentRow,
    ),
  };

  test('standing there seats the cut\'s camera — the timeline stands on its '
      'camera row', () {
    final session = onTheCameraRow(30);

    expect(session.selectedRow, cameraRow);
    expect(session.storyboardStandingRow, cameraRow);
    expect(session.activeCutId, b);
    expect(session.activeLayerId, const LayerId('b-cam'));
    expect(
      projectedLayerInHand(
        row: cameraRow,
        cut: session.activeCutOrNull,
        activeLayerId: session.activeLayerId,
      )?.id,
      const LayerId('b-cam'),
    );
  });

  test('🚨every button answers as the timeline\'s camera row does on the '
      'same cell — on a key and off one', () {
    for (final (globalFrame, ownFrame) in [(30, 6), (28, 4)]) {
      final storyboard = onTheCameraRow(globalFrame);
      final timeline = onTheTimelinesCameraRow(b, ownFrame);
      expect(
        answersOf(StoryboardToolbarPanelContext(storyboard), storyboard),
        answersOf(TimelineToolbarPanelContext(timeline), timeline),
        reason: 'at $globalFrame',
      );
    }
  });

  test('a press names a cut and a frame of its own — while it plays, the '
      'clock goes to where that frame plays', () {
    final session = open();
    seekStoryboardCutFrame(session, b, 6);
    expect((session.activeCutId, session.currentFrameIndex), (b, 6));

    final playing = open()..selectCut(b);
    final playback = playing.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    addTearDown(playback.stop);

    seekStoryboardCutFrame(playing, b, 6);

    expect(playback.playlistFrame, 6);
    expect(playing.playheadCursors.trackFrameNow(), 30);
  });

  test('＋ keys the cell it stands on', () {
    final session = onTheCameraRow(28);
    final panel = StoryboardToolbarPanelContext(session);

    expect(panel.canCreateInstance, isTrue);
    panel.createInstance();

    expect(keysOf(session, b), [2, 4, 6], reason: 'b\'s own frame at 28');
    expect(keysOf(session, a), [0, 12], reason: 'a is not touched');
  });

  test('Delete takes the key it stands on', () {
    final session = onTheCameraRow(30);
    final panel = StoryboardToolbarPanelContext(session);

    expect(panel.deleteSubject, PillSubject.cells);
    panel.deleteSelectionSubject();

    expect(keysOf(session, b), [2]);
  });

  test('Edit opens the key — the timeline\'s own cell', () {
    final session = onTheCameraRow(30);

    expect(
      StoryboardToolbarPanelContext(session).editTarget,
      isA<StoryboardEditTimelineCells>(),
    );
  });

  test('the flip walks it a frame at a time, into the next cut — still on '
      'its camera', () {
    final session = onTheCameraRow(23);

    session.frameVerbs.flipRow(forward: true);

    expect(session.editingGlobalFrame, 24);
    expect(session.activeCutId, b);
    expect(session.activeLayerId, const LayerId('b-cam'));
    expect(session.storyboardStandingRow, cameraRow);

    session.frameVerbs.flipRow(forward: false);
    expect(session.editingGlobalFrame, 23, reason: 'back, a frame');
  });

  /// Every button the row borrows, dark.
  final dark = isA<Map<String, Object?>>().having(
    (answers) => answers.values.toSet(),
    'answers',
    {false, PillSubject.nothing},
  );

  test('a gap holds no camera: the buttons are dark', () {
    final session = onTheCameraRow(50);
    final panel = StoryboardToolbarPanelContext(session);

    expect(session.activeCutOrNull, isNull, reason: '⛔전제');
    expect(answersOf(panel, session), dark);
    expect(panel.editTarget, isNull);
  });

  // ↩️Once the timeline picked another layer, this row stood on lent
  // nothing. I-126 (유저 2026-10-23: 「기본적으로 서로 서있는거
  // 동기화되도록」): the pick stands the storyboard on the V row now
  // (where_the_timeline_stands_the_storyboard_stands_test.dart).
}
