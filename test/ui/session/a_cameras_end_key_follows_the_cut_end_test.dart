import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
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

      expect(cutIn(session, a).duration, 4);
      expect(keysOf(session, a), {0: 0, 2: 12, 3: 23});
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

    test('🚨the front pushes the keys in too', () {
      final session = open();

      trim(session, a, TimelineBlockEdge.start, 20);

      expect(cutIn(session, a).duration, 4);
      expect(keysOf(session, a), {0: 0, 2: 12, 3: 23});
    });

    test('🚨past where the keys have frames it stops, each on its own — and '
        'the undo puts them all back', () {
      final session = open();

      trim(session, a, TimelineBlockEdge.end, -30);

      expect(cutIn(session, a).duration, 3);
      expect(keysOf(session, a), {0: 0, 1: 12, 2: 23});

      session.undo();
      expect(cutIn(session, a).duration, 24);
      expect(keysOf(session, a), {0: 0, 12: 12, 23: 23});
    });

    test('🚨a key in the middle with none on the end: the first drag goes '
        'straight through it (F-541)', () {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('middle'),
          name: 'Middle',
          createdAt: DateTime.utc(2026, 11, 2),
          tracks: [
            Track(
              id: const TrackId('t'),
              name: 'V',
              cuts: [
                cutOf('a', [0, 12]),
              ],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);

      trim(session, a, TimelineBlockEdge.end, -16);

      expect(cutIn(session, a).duration, 8);
      expect(keysOf(session, a), {0: 0, 7: 12});

      session.undo();
      expect(keysOf(session, a), {0: 0, 12: 12});
    });
  });

  test('🚨the floor counts the のりしろ an O.L asks as no length to trim', () {
    final session = open();
    session.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    expect(keysOf(session, a), {0: 0, 12: 12, 29: 23}, reason: '⛔전제');

    trim(session, a, TimelineBlockEdge.end, -20);

    expect(
      cutIn(session, a).duration,
      4,
      reason: 'drawn for ten, six of them the のりしろ',
    );
    expect(keysOf(session, a), {0: 0, 8: 12, 9: 23});
  });

  test('🚨drawn out from the front, the glued cut in front gives no frame '
      'past its own keys', () {
    final session = open();

    trim(session, b, TimelineBlockEdge.start, -20);

    expect(
      (cutIn(session, a).duration, cutIn(session, b).duration),
      (4, 44),
      reason: 'a gives twenty, pushing its keys in',
    );
    expect(keysOf(session, a), {0: 0, 2: 12, 3: 23});
  });

  test('…the gap between them spent first', () {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('gap'),
        name: 'Gap',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              cutOf('a', [0, 12, 23]),
              cutOf('b', [2, 23]).copyWith(leadingGapFrames: 4),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);

    trim(session, b, TimelineBlockEdge.start, -20);

    expect(
      (cutIn(session, a).duration, cutIn(session, b).duration),
      (8, 44),
      reason: 'b takes the four of the gap, then sixteen of a',
    );
  });

  group('a cut with a conte', () {
    /// Cut c: two panels of twelve, its camera keyed at [keys].
    EditorSessionManager withConte(List<int> keys) {
      Frame panel(String id) =>
          Frame(id: FrameId(id), duration: 1, strokes: const []);
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('conte'),
          name: 'Conte',
          createdAt: DateTime.utc(2026, 10, 9),
          tracks: [
            Track(
              id: const TrackId('t'),
              name: 'V',
              cuts: [
                cutOf('c', keys).copyWith(
                  layers: [
                    Layer(
                      id: const LayerId('c-conte'),
                      name: 'Conte',
                      kind: LayerKind.storyboard,
                      frames: [panel('p1'), panel('p2')],
                      timeline: const {
                        0: TimelineExposure.drawing(FrameId('p1'), length: 12),
                        12: TimelineExposure.drawing(FrameId('p2'), length: 12),
                      },
                    ),
                    Layer(
                      id: const LayerId('c-cam'),
                      name: 'Camera',
                      kind: LayerKind.camera,
                      frames: const [],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      return session;
    }

    List<int> panelsOf(EditorSessionManager session) => [
      ...cutIn(session, const CutId('c')).layers
          .singleWhere((layer) => layer.kind == LayerKind.storyboard)
          .timeline
          .entries
          .where((entry) => !entry.value.ghost)
          .map((entry) => entry.key),
    ];

    test('🚨its end — the conte\'s last comma — pushes the camera\'s keys '
        'too, as far as its last panel lets it', () {
      final session = withConte([0, 16, 23]);

      trim(session, const CutId('c'), TimelineBlockEdge.end, -10);

      expect(cutIn(session, const CutId('c')).duration, 14);
      expect(panelsOf(session), [0, 12], reason: 'the last panel runs to 14');
      expect(keysOf(session, const CutId('c')), {0: 0, 12: 16, 13: 23});

      session.undo();
      expect(keysOf(session, const CutId('c')), {0: 0, 16: 16, 23: 23});
    });

    test('an inner panel\'s front trades frames inside its cut — its length, '
        'and its camera, stay', () {
      final session = withConte([0, 22, 23]);

      expect(
        session.edgeDrag.beginCutEdgeDrag(
          cutId: const CutId('c'),
          edge: TimelineBlockEdge.start,
          panelIndex: 1,
        ),
        isTrue,
        reason: '⛔전제',
      );
      session.edgeDrag.updateCutEdgeDrag(4);
      session.edgeDrag.endCutEdgeDrag();

      expect(panelsOf(session), [0, 16], reason: 'the division moved');
      expect(cutIn(session, const CutId('c')).duration, 24);
      expect(keysOf(session, const CutId('c')), {0: 0, 22: 22, 23: 23});
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
