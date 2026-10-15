import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformTrackWithPositionDragged;

/// 🗣️I-73-camera-row-Q2 (유저 2026-10-09: 「콘티처럼 컷밖으로 못나가게
/// 클리핑」 → `own-frames`): a camera key lives on the frames its cut is
/// drawn for — its place, and the のりしろ an O.L asks of it — and the
/// verbs that make one make it nowhere else.
///
/// Cuts a [0, 24) and b [24, 48), the last; a's camera keyed at 0, b's at
/// 2. Past b's end the timeline still has cells — the runway — and the
/// camera row has them too.
void main() {
  const a = CutId('a');
  const b = CutId('b');

  Cut cutOf(String id, List<int> keys) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: CutCamera(
      keyframes: {
        for (final frame in keys)
          frame: CameraPose(center: CanvasPoint(x: 320.0 + frame, y: 180)),
      },
    ),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  EditorSessionManager open({List<int> bKeys = const [2]}) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('inside'),
        name: 'Inside',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              cutOf('a', [0]),
              cutOf('b', bKeys),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// The timeline, stood on [id]'s camera row at its own [frame].
  EditorSessionManager onTheCameraRow(CutId id, int frame) => open()
    ..selectCut(id)
    ..standOnRow(LayerRowAddress(LayerId('${id.value}-cam')))
    ..selectFrameIndex(frame);

  List<int> keysOf(EditorSessionManager session, CutId id) => [
    ...session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .singleWhere((cut) => cut.id == id)
        .camera
        .keyframes
        .keys,
  ];

  List<int> positionKeysOf(EditorSessionManager session, CutId id) => [
    ...session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .singleWhere((cut) => cut.id == id)
        .camera
        .track
        .position
        .keys
        .keys,
  ];

  /// [frame] of b's Position lane: a ◆ toggled there, or a value typed.
  void keyAt(EditorSessionManager session, int frame) =>
      session.laneVerbs.toggleLaneKeyAt(
        const LayerId('b-cam'),
        'position',
        frame,
        frameIsGlobal: false,
        description: 'Key',
      );
  void typeAt(EditorSessionManager session, int frame) =>
      session.laneVerbs.setLaneValueAt(
        const LayerId('b-cam'),
        'position',
        frame,
        '10, 10',
        frameIsGlobal: false,
        description: 'Type',
        scaleLinked: true,
      );

  /// b's Position lane picked up at [frame] and slid by each of [deltas].
  void slideLane(EditorSessionManager session, int frame, List<int> deltas) {
    session.updateLaneRangeSelectionDrag(
      layerId: const LayerId('b-cam'),
      laneId: 'position',
      anchorIndex: frame,
      headIndex: frame,
      spanLaneIds: const [],
    );
    expect(session.laneMove.beginLaneRangeMoveDrag(), isTrue);
    for (final delta in deltas) {
      session.laneMove.updateLaneRangeMoveDrag(frameDelta: delta);
    }
    session.laneMove.endLaneRangeMoveDrag();
  }

  test('the ＋ past the cut\'s end is dark, and the key it would make is '
      'not made', () {
    final session = onTheCameraRow(b, 30);
    final panel = TimelineToolbarPanelContext(session);
    expect(
      (session.activeCutId, session.currentFrameIndex),
      (b, 30),
      reason: '⛔전제: on the runway past b',
    );

    expect(panel.canCreateInstance, isFalse);
    session.camera.setCameraKeyframeAtCurrentFrame(
      session.camera.cameraPoseAtCurrentFrame,
    );
    expect(keysOf(session, b), [2]);

    // LIVENESS: on its own frames the ＋ makes one.
    session.selectFrameIndex(23);
    expect(panel.canCreateInstance, isTrue);
    panel.createInstance();
    expect(keysOf(session, b), [2, 23]);
  });

  test('🚨the のりしろ an O.L asks is the cut\'s own: a key is made there', () {
    final session = onTheCameraRow(a, 0)
      ..transitions.updateTransitionInstructions({
        18: const InstructionEvent(instructionId: 'ol', length: 12),
      });
    // a leaves through the O.L: its own frames run to 30.
    session.selectFrameIndex(28);
    final panel = TimelineToolbarPanelContext(session);

    expect(panel.canCreateInstance, isTrue);
    panel.createInstance();
    expect(keysOf(session, a), [0, 28]);

    session.selectFrameIndex(30);
    expect(panel.canCreateInstance, isFalse, reason: 'past the のりしろ');
  });

  test('a range keys the frames of it the cut is drawn for, and no more', () {
    final session = open()..selectCut(b);

    final command = session.camera.cameraKeysCommandForRange(
      const TimelineFrameRangeSelection(
        layerId: LayerId('b-cam'),
        startIndex: 21,
        endIndexExclusive: 28,
      ),
    );
    command!.execute();

    expect(keysOf(session, b), [2, 21, 22, 23]);
  });

  test('a key fits on the frames the cut is drawn for, and nowhere else', () {
    expect(cameraKeyFits(0, drawnFrameCount: 24), isTrue);
    expect(cameraKeyFits(23, drawnFrameCount: 24), isTrue);
    expect(cameraKeyFits(24, drawnFrameCount: 24), isFalse);
    expect(cameraKeyFits(-1, drawnFrameCount: 24), isFalse);
  });

  group('…nor put out of it: a write that would is not made', () {
    test('a ◆ or a value at a frame past the end keys nothing, and a scrub '
        'there shows nothing — on its own frames they key', () {
      final session = onTheCameraRow(b, 30);

      keyAt(session, 30);
      typeAt(session, 31);
      session.laneVerbs.previewLaneValueAt(
        const LayerId('b-cam'),
        'position',
        32,
        '10, 10',
        frameIsGlobal: false,
        scaleLinked: true,
      );
      expect(session.dragPreview.value, isNull);
      expect(positionKeysOf(session, b), [2]);

      // LIVENESS
      keyAt(session, 20);
      typeAt(session, 23);
      expect(positionKeysOf(session, b), [2, 20, 23]);
    });

    test('🚨the frame dragged on the canvas past the end moves nothing, '
        'shown or released', () {
      final session = onTheCameraRow(b, 30);
      TransformTrack moved(TransformTrack track, int frame) =>
          transformTrackWithPositionDragged(
            track,
            frameIndex: frame,
            position: CanvasPoint(x: 1, y: 1),
          );

      session.laneVerbs.previewLayerTransformAtPlayhead(
        const LayerId('b-cam'),
        moved,
      );
      expect(session.dragPreview.value, isNull);
      session.laneVerbs.editLayerTransformAtPlayhead(
        const LayerId('b-cam'),
        moved,
        description: 'Move camera',
      );
      expect(positionKeysOf(session, b), [2]);

      // LIVENESS
      session.selectFrameIndex(23);
      session.laneVerbs.editLayerTransformAtPlayhead(
        const LayerId('b-cam'),
        moved,
        description: 'Move camera',
      );
      expect(positionKeysOf(session, b), [2, 23]);
    });

    test('🚨a lane\'s keys slid toward the end stop on its last frame: the '
        'step past it holds the one before', () {
      final session = onTheCameraRow(b, 0);

      slideLane(session, 2, [21, 22]);

      expect(positionKeysOf(session, b), [23]);
      expect(session.laneRangeSelection.value!.startIndex, 23);
    });

    test('🚨…and so do the keys a range of cells carries', () {
      final session = onTheCameraRow(b, 0)
        ..updateFrameRangeSelectionDrag(
          layerId: const LayerId('b-cam'),
          anchorIndex: 2,
          headIndex: 2,
        );

      expect(
        session.rangeMove.beginFrameRangeMoveDrag(const LayerId('b-cam')),
        isTrue,
      );
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 21);
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 22);
      session.rangeMove.endFrameRangeMoveDrag();

      expect(keysOf(session, b), [23]);
    });

    test('a key already out — an O.L can still leave one there — is not put '
        'out by a write: kept while others are made, brought back in or '
        'taken away, and not moved further out', () {
      final session = open(bKeys: const [2, 30])..selectCut(b);
      expect(positionKeysOf(session, b), [2, 30], reason: '⛔전제');

      slideLane(session, 30, [1]);
      expect(positionKeysOf(session, b), [2, 30], reason: 'not further out');

      keyAt(session, 10);
      expect(positionKeysOf(session, b), [2, 10, 30]);

      slideLane(session, 30, [-10]);
      expect(positionKeysOf(session, b), [2, 10, 20]);
      session.undo();

      keyAt(session, 30);
      expect(positionKeysOf(session, b), [2, 10]);
    });
  });
}
