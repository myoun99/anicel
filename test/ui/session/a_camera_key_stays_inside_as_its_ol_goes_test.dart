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
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show projectWithTimelineDragPreview;

/// 🗣️I-73-camera-row-Q7 (유저 2026-10-09): 「컷 길이 줄이기와 똑같이 — 안쪽
/// 키 앞에서 멈춤」 · 「OL삭제한다거나 하면 키를 컷 길이 줄이는거랑 동일하게 그
/// 사라진 코마만큼 컷길이 움직인거랑 동일한 규칙으로 키를 앞당긴다던가 함」 — a
/// のりしろ a drag makes shorter stops short of the camera keys on it; one
/// that goes at once brings them in by the frames that went, and its undo
/// puts them back.
///
/// Cuts a [0, 24), b [24, 48) and c [48, 72), and an O.L over 18..29 across
/// a|b: a is drawn for its frames 0..29 (six past its end), b for 0..29
/// (six before its conte). a's camera keys 0, 20, 27 and 29; b's 0, 27 and
/// 29; c's 0 and 23. A key's pose is made with its frame, so a key that
/// moved still says where it came from.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const c = CutId('c');

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

  const ol = {18: InstructionEvent(instructionId: 'ol', length: 12)};

  EditorSessionManager open({List<int> aKeys = const [0, 20, 27, 29]}) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('ol-keys'),
        name: 'O.L keys',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              cutOf('a', aKeys),
              cutOf('b', [0, 27, 29]),
              cutOf('c', [0, 23]),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.transitions.updateTransitionInstructions(ol);
    return session;
  }

  Cut cutIn(EditorSessionManager session, CutId id) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .singleWhere((cut) => cut.id == id);

  /// [id]'s camera keys, each with the frame its pose was made with.
  Map<int, double> keysOf(EditorSessionManager session, CutId id) => {
    for (final entry in cutIn(session, id).camera.keyframes.entries)
      entry.key: entry.value.center.x - 320,
  };

  Map<int, int> spansOf(EditorSessionManager session) => {
    for (final entry
        in session.activeTrack.transitionLayer.instructions.entries)
      entry.key: entry.value.length,
  };

  void dragEdge(EditorSessionManager session, TimelineBlockEdge edge, int by) {
    expect(
      session.edgeDrag.beginTransitionEdgeDrag(spanStartIndex: 18, edge: edge),
      isTrue,
      reason: '⛔전제',
    );
    session.edgeDrag.updateTransitionEdgeDrag(by);
    session.edgeDrag.endTransitionEdgeDrag();
  }

  test('⛔the fixture: the O.L draws a and b for thirty frames each, the '
      'keys where they were made', () {
    final session = open();
    expect(keysOf(session, a), {0: 0, 20: 20, 27: 27, 29: 29});
    expect(keysOf(session, b), {0: 0, 27: 27, 29: 29});
  });

  group('the O.L taken away at once', () {
    test('🚨the keys on the frames that went come in by six — a\'s past its '
        'end, b\'s before its conte — and the undo puts them back', () {
      final session = open();

      session.transitions.updateTransitionInstructions(const {});

      expect(keysOf(session, a), {0: 0, 20: 20, 21: 27, 23: 29});
      expect(keysOf(session, b), {0: 0, 21: 27, 23: 29});

      session.undo();
      expect(keysOf(session, a), {0: 0, 20: 20, 27: 27, 29: 29});
      expect(keysOf(session, b), {0: 0, 27: 27, 29: 29});

      session.redo();
      expect(keysOf(session, a), {0: 0, 20: 20, 21: 27, 23: 29});
    });

    test('a key coming in onto another takes its frame '
        '(I-73-camera-row-Q8) — and the undo brings both back', () {
      final session = open(aKeys: [0, 21, 27]);

      session.transitions.updateTransitionInstructions(const {});
      expect(keysOf(session, a), {0: 0, 21: 27});

      session.undo();
      expect(keysOf(session, a), {0: 0, 21: 21, 27: 27});
    });

    test('🚨b moved off it brings b\'s in — c, arriving through it now, '
        'sends its end key out — and one undo puts both back', () {
      final session = open();
      session.selectCut(b);

      session.cutVerbs.moveActiveCutRight();

      expect(
        spansOf(session),
        {18: 12},
        reason: '⛔전제: the O.L stays on a\'s end, over a|c now',
      );
      expect(keysOf(session, b), {0: 0, 21: 27, 23: 29});
      expect(keysOf(session, c), {0: 0, 29: 23});

      session.undo();
      expect(keysOf(session, b), {0: 0, 27: 27, 29: 29});
      expect(keysOf(session, c), {0: 0, 23: 23});
    });
  });

  group('a drag that makes the のりしろ shorter', () {
    test('🚨its end stops short of a\'s keys — a frame in, where 27 still '
        'stands and the end key comes in with the end', () {
      final session = open();

      dragEdge(session, TimelineBlockEdge.end, -5);

      expect(spansOf(session), {18: 11});
      expect(keysOf(session, a), {0: 0, 20: 20, 27: 27, 28: 29});
    });

    test('🚨its start stops short of b\'s', () {
      final session = open();

      dragEdge(session, TimelineBlockEdge.start, 5);

      expect(spansOf(session), {19: 11});
      expect(keysOf(session, b), {0: 0, 27: 27, 28: 29});
    });

    test('🚨the span slid along holds its last step that keeps them', () {
      final session = open();
      final row = session.activeTrack.transitionLayer.id;
      session.updateTrackRowRangeSelectionByFrame(
        layerId: row,
        anchorGlobalFrame: 18,
        headGlobalFrame: 29,
      );
      expect(session.rangeMove.beginTrackRangeMoveDrag(row), isTrue);

      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3);
      session.rangeMove.endFrameRangeMoveDrag();

      expect(spansOf(session), {19: 12}, reason: 'b keeps 27 at a 5-frame head');
      expect(keysOf(session, b), {0: 0, 27: 27, 28: 29});
      expect(keysOf(session, a), {0: 0, 20: 20, 27: 27, 30: 29});
    });

    test('drawn out instead, nothing stops it — the end key goes out', () {
      final session = open();

      dragEdge(session, TimelineBlockEdge.end, 4);

      expect(spansOf(session), {18: 16});
      expect(keysOf(session, a), {0: 0, 20: 20, 27: 27, 33: 29});
    });

    test('🚨the end key follows the edge under the hand, in the cut and on '
        'the storyboard — and the release keeps it there', () {
      final session = open();
      session.selectCut(a);
      expect(
        session.edgeDrag.beginTransitionEdgeDrag(
          spanStartIndex: 18,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );

      session.edgeDrag.updateTransitionEdgeDrag(2);

      expect(
        session.camera.activeCutCameraTrack!.position.keys.keys,
        [0, 20, 27, 31],
        reason: 'the cut\'s rows and canvas read this',
      );
      final shown = projectWithTimelineDragPreview(
        session.repository.requireProject(),
        session.dragPreview.value,
      );
      expect(
        shown.tracks.single.cuts.first.camera.keyframes.keys,
        [0, 20, 27, 31],
        reason: 'the storyboard draws the project under the preview',
      );
      expect(keysOf(session, a).keys, [0, 20, 27, 29], reason: 'not yet');

      session.edgeDrag.endTransitionEdgeDrag();
      expect(keysOf(session, a).keys, [0, 20, 27, 31]);
    });

    test('a key a file left past a cut\'s end holds no drag out — nor in: '
        'the keys inside are the floor', () {
      final session = open(aKeys: [0, 20, 40]);

      dragEdge(session, TimelineBlockEdge.end, 2);
      expect(spansOf(session), {18: 14});

      session.undo();
      dragEdge(session, TimelineBlockEdge.end, -5);
      expect(spansOf(session), {18: 7}, reason: 'a is drawn for 25 — 20 kept');
      expect(keysOf(session, a), {0: 0, 20: 20, 40: 40});
    });
  });
}
