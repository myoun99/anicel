import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// A track-SE row's blocks live on the TRACK's frames, so a verb worked in
/// a cut that does not start at frame 0 has to carry the cut's cells onto
/// that axis before it touches a block. In the first cut the two axes
/// coincide and a verb that skipped the carry looks right.
///
/// 🧪Pinned when the audit's nineteenth family (2026-09-28) moved the carry
/// (`commitBlockStart`) into `TrackSeDisplay`: a mutant that skipped it at
/// each asker — the range move, the delete, the shove, the bulk comma drag
/// — survived every suite, because every suite worked in the first cut.
void main() {
  const seRow = LayerId('se-row');
  const cel = LayerId('cut-2-cel');

  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(
        id: LayerId('$id-cel'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
    ],
  );

  Frame sound(String id, int length) =>
      Frame(id: FrameId(id), duration: length, name: id, strokes: const []);

  /// Cut 1 is global [0, 8), cut 2 is [8, 14). The SE row holds `early` in
  /// cut 1 at global 2 and `mid` / `late` in cut 2 at global 10 and 13 —
  /// cut-local 2 and 5.
  EditorSessionManager sessionInTheSecondCut() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('se-later-cut'),
        name: 'SE later cut',
        createdAt: DateTime.utc(2026, 9, 28),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [cut('cut-1', 8), cut('cut-2', 6)],
            seLayers: [
              Layer(
                id: seRow,
                name: 'S1',
                kind: LayerKind.se,
                frames: [sound('early', 2), sound('mid', 2), sound('late', 1)],
                timeline: {
                  2: const TimelineExposure.drawing(FrameId('early'), length: 2),
                  10: const TimelineExposure.drawing(FrameId('mid'), length: 2),
                  13: const TimelineExposure.drawing(FrameId('late'), length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    s.selectCut(const CutId('cut-2'));
    return s;
  }

  Map<int, TimelineExposure> global(EditorSessionManager s) =>
      s.repository.requireProject().tracks.single.seLayers.single.timeline;

  test('a range move of the block carries it on the track', () {
    final s = sessionInTheSecondCut();
    s.updateFrameRangeSelectionDrag(
      layerId: seRow,
      anchorIndex: 2,
      headIndex: 3,
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(global(s)[11]?.frameId, const FrameId('mid'));
    expect(global(s)[10], isNull);
    expect(global(s)[2]?.frameId, const FrameId('early'));
  });

  test('deleting the selected block deletes THAT block', () {
    final s = sessionInTheSecondCut();
    s.updateFrameRangeSelectionDrag(
      layerId: seRow,
      anchorIndex: 2,
      headIndex: 3,
    );

    s.cells.deleteCellAtCurrentFrame();

    expect(global(s)[10], isNull);
    expect(global(s)[2]?.frameId, const FrameId('early'));
  });

  test('a shove from the selection pushes from the block, not from the '
      'cut-local number', () {
    final s = sessionInTheSecondCut();
    s.updateFrameRangeSelectionDrag(
      layerId: seRow,
      anchorIndex: 2,
      headIndex: 3,
    );

    s.blockShift.pushFrames(1);

    expect(global(s)[11]?.frameId, const FrameId('mid'));
    expect(
      global(s)[2]?.frameId,
      const FrameId('early'),
      reason: 'a block before the anchor on the track never moves',
    );
  });

  test('a comma drag whose selection spans the row retimes the block on '
      'the track', () {
    final s = sessionInTheSecondCut();
    s.selectLayer(cel);
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    s.updateFrameRangeSelectionDrag(
      layerId: cel,
      anchorIndex: 2,
      headIndex: 2,
      headLayerId: seRow,
    );
    expect(
      s.frameRangeSelection.value!.spanLayerIds,
      containsAll([cel, seRow]),
      reason: '⛔premise: the selection covers both rows',
    );

    expect(
      s.edgeDrag.beginExposureEdgeDrag(
        layerId: cel,
        blockStartIndex: 2,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.edgeDrag.updateExposureEdgeDrag(1);
    s.edgeDrag.endExposureEdgeDrag();

    expect(global(s)[10]?.length, 3, reason: 'the SE block retimed with it');
    expect(global(s)[2]?.length, 2, reason: 'the block in cut 1 is not it');
  });
}
