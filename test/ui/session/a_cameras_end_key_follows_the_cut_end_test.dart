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
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️I-73-camera-row-Q4 (유저 2026-10-09): 「끝 칸의 키는 늘릴때나 줄일때
/// 컷 끝에 붙어있기만 하면되. 위치만 이동되도록. 밖엔 애초에
/// 존재못하게하는게 지금구조잖아. 밖으로 나갈일도없어」 — through the verbs
/// that change a cut's length, and the undo of each.
///
/// Cuts a [0, 24) and b [24, 48). a's camera keys 0, 12 and 23 — the last
/// on its last frame; b's 2 and 23.
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

  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('ends'),
        name: 'Ends',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              cutOf('a', [0, 12, 23]),
              cutOf('b', [2, 23]),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  Cut cutIn(EditorSessionManager session, CutId id) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .singleWhere((cut) => cut.id == id);

  /// [id]'s camera keys, each with its pose's x less 320 — the frame whose
  /// pose it was made with.
  Map<int, double> keysOf(EditorSessionManager session, CutId id) => {
    for (final entry in cutIn(session, id).camera.keyframes.entries)
      entry.key: entry.value.center.x - 320,
  };

  void trim(
    EditorSessionManager session,
    CutId id,
    TimelineBlockEdge edge,
    int delta,
  ) {
    expect(
      session.edgeDrag.beginCutEdgeDrag(cutId: id, edge: edge),
      isTrue,
      reason: '⛔전제',
    );
    session.edgeDrag.updateCutEdgeDrag(delta);
    session.edgeDrag.endCutEdgeDrag();
  }

  group('a cut\'s end trimmed', () {
    test('🚨shorter: the key on its last frame comes in with it — and undo '
        'carries it back', () {
      final session = open();

      trim(session, a, TimelineBlockEdge.end, -8);

      expect(cutIn(session, a).duration, 16, reason: '⛔전제');
      expect(keysOf(session, a), {0: 0, 12: 12, 15: 23});
      expect(keysOf(session, b), {2: 2, 23: 23}, reason: 'b is not touched');

      session.undo();
      expect(keysOf(session, a), {0: 0, 12: 12, 23: 23});
    });

    test('🚨longer: it goes out with it', () {
      final session = open();

      trim(session, a, TimelineBlockEdge.end, 6);

      expect(cutIn(session, a).duration, 30, reason: '⛔전제');
      expect(keysOf(session, a), {0: 0, 12: 12, 29: 23});

      session.undo();
      expect(keysOf(session, a), {0: 0, 12: 12, 23: 23});
    });

    test('🚨the end stops short of every other key — none is put out', () {
      final session = open();

      trim(session, a, TimelineBlockEdge.end, -20);

      expect(
        cutIn(session, a).duration,
        14,
        reason: 'key 12 stays, and the end key takes frame 13',
      );
      expect(keysOf(session, a), {0: 0, 12: 12, 13: 23});
    });

    test('and the hand shows it before the release does', () {
      final session = open()..selectCut(a);
      expect(
        session.edgeDrag.beginCutEdgeDrag(
          cutId: a,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );

      session.edgeDrag.updateCutEdgeDrag(6);
      expect(
        session.camera.activeCutCameraTrack!.keyedFrames,
        {0, 12, 29},
        reason: 'the active cut\'s camera as the timeline and the canvas '
            'read it',
      );
      expect(keysOf(session, a).keys, [0, 12, 23], reason: 'unwritten');

      session.edgeDrag.cancelCutEdgeDrag();
      expect(session.camera.activeCutCameraTrack!.keyedFrames, {0, 12, 23});
    });
  });

  group('a cut\'s front trimmed', () {
    test('🚨drawn out: the cut grows, the glued cut in front gives the '
        'frames, and each one\'s end key keeps to its own end', () {
      final session = open();

      trim(session, b, TimelineBlockEdge.start, -5);

      expect(
        (cutIn(session, a).duration, cutIn(session, b).duration),
        (19, 29),
        reason: '⛔전제: the glued pair trade frames across the boundary',
      );
      expect(keysOf(session, a), {0: 0, 12: 12, 18: 23});
      expect(keysOf(session, b), {2: 2, 28: 23});

      session.undo();
      expect(keysOf(session, a), {0: 0, 12: 12, 23: 23});
      expect(keysOf(session, b), {2: 2, 23: 23});
    });

    test('🚨the front stops short of every other key too', () {
      final session = open();

      trim(session, a, TimelineBlockEdge.start, 20);

      expect(cutIn(session, a).duration, 14);
      expect(keysOf(session, a), {0: 0, 12: 12, 13: 23});
    });
  });

  test('🚨an O.L across a cut\'s end makes its own frames run on, and its '
      'end key with them — taking the O.L away brings it back', () {
    final session = open();

    session.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    // a leaves through the O.L: drawn to 30, its last frame 29.
    expect(keysOf(session, a), {0: 0, 12: 12, 29: 23});

    session.undo();
    expect(keysOf(session, a), {0: 0, 12: 12, 23: 23});
  });
}
