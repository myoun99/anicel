import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-227 (유저 2026-09-29/30): 「ol주는컷은 콘티블록의 마지막블록을 늘리고
/// 받는컷은 처음블록을 늘리라」 · 「콘티블록의 첫블록을 여백길이 이하로
/// 못줄이게하는게 근본적 맞지않나? … 예를들어 ol여백 12코마면 콘티 첫블록을
/// 12밑으로 못줄이거나」.
///
/// Two 48-frame cuts, each with a two-panel conte (20 + 28), and an O.L of
/// 24 frames centred on their boundary — 12 frames of のりしろ on each side.
/// The のりしろ part of a block is the O.L's, derived: no edit reaches it,
/// and the panel's own part keeps its one-frame floor, so the block never
/// drops below 12 + 1.
void main() {
  const giving = CutId('a');
  const receiving = CutId('b');

  Layer conte(String cut) => Layer(
    id: LayerId('conte-$cut'),
    name: 'conte',
    kind: LayerKind.storyboard,
    frames: [
      Frame(id: FrameId('$cut-p1'), duration: 1, strokes: const []),
      Frame(id: FrameId('$cut-p2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-p1'), length: 20),
      20: TimelineExposure.drawing(FrameId('$cut-p2'), length: 28),
    },
  );

  Cut cut(CutId id) => Cut(
    id: id,
    name: id.value,
    duration: 48,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: [conte(id.value)],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut(giving), cut(receiving)],
          ),
        ],
      ),
    );
    s.transitions.updateTransitionInstructions({
      36: const InstructionEvent(instructionId: 'ol', length: 24),
    });
    return s;
  }

  Layer conteRow(EditorSessionManager s, CutId cutId) => requireLayer(
    s.repository.requireProject(),
    cutId: cutId,
    layerId: LayerId('conte-${cutId.value}'),
  );

  FrameId? shownAt(EditorSessionManager s, CutId cutId, int frame) =>
      exposedFrameIdAt(conteRow(s, cutId).timeline, frame);

  /// How many of the cut's first frames its first panel is shown for.
  int firstBlockFrames(EditorSessionManager s, CutId cutId) {
    final first = shownAt(s, cutId, 0);
    var frame = 0;
    while (shownAt(s, cutId, frame) == first) {
      frame += 1;
    }
    return frame;
  }

  test('the RECEIVING cut\'s first panel holds back over its 12 frames, '
      'and its second keeps the conte\'s time', () {
    final s = session();
    addTearDown(s.dispose);
    expect(firstBlockFrames(s, receiving), 12 + 20);
    expect(shownAt(s, receiving, 32), const FrameId('b-p2'));
    expect(
      shownAt(s, receiving, 59),
      const FrameId('b-p2'),
      reason: 'the last panel reaches the drawn end, 12 + 48',
    );
  });

  test('the GIVING cut\'s last panel holds 12 frames past the red line', () {
    final s = session();
    addTearDown(s.dispose);
    expect(shownAt(s, giving, 47), const FrameId('a-p2'));
    expect(shownAt(s, giving, 59), const FrameId('a-p2'));
    expect(shownAt(s, giving, 60), isNull);
  });

  test('dragging the receiving cut\'s first panel shorter stops at ONE '
      'conte frame — the block never goes below 12 + 1', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(receiving);
    // The first panel's real block starts where the conte does: 12.
    expect(
      s.edgeDrag.beginExposureEdgeDrag(
        layerId: const LayerId('conte-b'),
        blockStartIndex: 12,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.edgeDrag.updateExposureEdgeDrag(-100);
    s.edgeDrag.endExposureEdgeDrag();
    expect(firstBlockFrames(s, receiving), 12 + 1);
    expect(shownAt(s, receiving, 13), const FrameId('b-p2'));
  });

  test('pulling the giving cut\'s red end line in stops at the last panel\'s '
      'one frame', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(giving);
    expect(
      s.edgeDrag.beginCutEdgeDrag(
        cutId: giving,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.edgeDrag.updateCutEdgeDrag(-100);
    s.edgeDrag.endCutEdgeDrag();
    final cutNow = s.repository.requireProject().tracks.single.cuts.first;
    expect(cutNow.duration, 20 + 1, reason: 'the last panel keeps one frame');
    expect(shownAt(s, giving, 20), const FrameId('a-p2'));
  });
}
