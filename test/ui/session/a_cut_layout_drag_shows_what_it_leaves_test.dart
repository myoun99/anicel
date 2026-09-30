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
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// A drag that moves where a cut starts or ends shows, under the hand, the
/// rows its release leaves — the のりしろ holds and the conte start an O.L
/// asks of the cuts it joins included (F-227). Those two are settled when
/// the project is WRITTEN, from the new layout; a preview that skipped the
/// settle showed the holds gone and the receiving cut's panels where the
/// old のりしろ put them, then jumped on release.
///
/// Two 48-frame cuts, each with a two-panel conte (20 + 28), and an O.L of
/// 24 frames centred on their boundary. Every verb that re-lays the cuts
/// is dragged, held, and read on both surfaces — the timeline's row gate
/// ([timelineDragPreviewLayerFor]) and the storyboard's project
/// ([projectWithTimelineDragPreview]) — then released and read again.
void main() {
  const giving = CutId('a');
  const receiving = CutId('b');

  LayerId rowOf(CutId cutId) => LayerId('conte-${cutId.value}');

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

  Layer conteRow(Project project, CutId cutId) =>
      requireLayer(project, cutId: cutId, layerId: rowOf(cutId));

  String cells(Map<int, TimelineExposure> timeline) => [
    for (final MapEntry(:key, :value) in timeline.entries)
      '$key:${value.frameId?.value}x${value.length}'
          '${value.ghost ? ' held' : ''}',
  ].join(', ');

  /// Both conte rows as the timeline and the storyboard show them.
  Map<String, String> onScreen(
    EditorSessionManager s,
    Layer Function(CutId cutId) timelineRow,
    Project storyboard,
  ) => {
    for (final cutId in [giving, receiving]) ...{
      'timeline ${cutId.value}': cells(timelineRow(cutId).timeline),
      'storyboard ${cutId.value}': cells(
        conteRow(storyboard, cutId).timeline,
      ),
    },
  };

  void expectTheHandShowsTheRelease({
    required bool Function(EditorSessionManager s) begin,
    required void Function(EditorSessionManager s) step,
    required void Function(EditorSessionManager s) release,
  }) {
    final s = session();
    addTearDown(s.dispose);
    expect(begin(s), isTrue);
    step(s);
    final preview = s.dragPreview.value;
    expect(preview, isNotNull, reason: 'fixture: the drag moved something');
    final committed = s.repository.requireProject();
    final midDrag = onScreen(
      s,
      (cutId) =>
          timelineDragPreviewLayerFor(preview, rowOf(cutId)) ??
          conteRow(committed, cutId),
      projectWithTimelineDragPreview(committed, preview),
    );
    release(s);
    final left = s.repository.requireProject();
    expect(
      midDrag,
      onScreen(s, (cutId) => conteRow(left, cutId), left),
    );
  }

  for (final delta in [4, -4]) {
    test('the receiving cut\'s front edge, $delta frames', () {
      expectTheHandShowsTheRelease(
        begin: (s) => s.edgeDrag.beginCutEdgeDrag(
          cutId: receiving,
          edge: TimelineBlockEdge.start,
        ),
        step: (s) => s.edgeDrag.updateCutEdgeDrag(delta),
        release: (s) => s.edgeDrag.endCutEdgeDrag(),
      );
    });

    test('the giving cut\'s red end line, $delta frames', () {
      expectTheHandShowsTheRelease(
        begin: (s) => s.edgeDrag.beginCutEdgeDrag(
          cutId: giving,
          edge: TimelineBlockEdge.end,
        ),
        step: (s) => s.edgeDrag.updateCutEdgeDrag(delta),
        release: (s) => s.edgeDrag.endCutEdgeDrag(),
      );
    });
  }

  test('the giving cut\'s front edge', () {
    expectTheHandShowsTheRelease(
      begin: (s) => s.edgeDrag.beginCutEdgeDrag(
        cutId: giving,
        edge: TimelineBlockEdge.start,
      ),
      step: (s) => s.edgeDrag.updateCutEdgeDrag(4),
      release: (s) => s.edgeDrag.endCutEdgeDrag(),
    );
  });

  test('the receiving cut\'s second panel traded with its first', () {
    expectTheHandShowsTheRelease(
      begin: (s) => s.edgeDrag.beginCutEdgeDrag(
        cutId: receiving,
        edge: TimelineBlockEdge.start,
        panelIndex: 1,
      ),
      step: (s) => s.edgeDrag.updateCutEdgeDrag(4),
      release: (s) => s.edgeDrag.endCutEdgeDrag(),
    );
  });

  test('the receiving cut\'s red end line', () {
    expectTheHandShowsTheRelease(
      begin: (s) => s.edgeDrag.beginCutEdgeDrag(
        cutId: receiving,
        edge: TimelineBlockEdge.end,
      ),
      step: (s) => s.edgeDrag.updateCutEdgeDrag(4),
      release: (s) => s.edgeDrag.endCutEdgeDrag(),
    );
  });

  test('both of the giving cut\'s panels retimed at once — its red end line '
      'rides the selection', () {
    expectTheHandShowsTheRelease(
      begin: (s) {
        s.selectCut(giving);
        s.frameRangeSelection.value = TimelineFrameRangeSelection(
          layerId: rowOf(giving),
          startIndex: 0,
          endIndexExclusive: 48,
        );
        return s.edgeDrag.beginExposureEdgeDrag(
          layerId: rowOf(giving),
          blockStartIndex: 20,
          edge: TimelineBlockEdge.end,
        );
      },
      step: (s) => s.edgeDrag.updateExposureEdgeDrag(4),
      release: (s) => s.edgeDrag.endExposureEdgeDrag(),
    );
  });

  test('the receiving cut moved along its track', () {
    expectTheHandShowsTheRelease(
      begin: (s) => s.cutMove.beginCutMoveDrag(receiving),
      step: (s) => s.cutMove.updateCutMoveDrag(4),
      release: (s) => s.cutMove.endCutMoveDrag(),
    );
  });

  test('the receiving cut moved ahead of the giving one', () {
    expectTheHandShowsTheRelease(
      begin: (s) => s.cutMove.beginCutMoveDrag(receiving),
      step: (s) => s.cutMove.updateCutMoveDrag(-48),
      release: (s) => s.cutMove.endCutMoveDrag(),
    );
  });
}
