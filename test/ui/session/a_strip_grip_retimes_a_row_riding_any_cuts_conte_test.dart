import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

import '../../helpers/run_edge_fixtures.dart';

/// 🗣️I-73 — the drawn proposal 유저 took on 2026-10-08, of a row riding
/// the conte on the storyboard: 「엣지 — 블록의 양 끝」.
///
/// The strip shows every cut's rows at once, so a grip on one names its
/// cut: the block is re-timed as its grip on the timeline re-times it —
/// alone, the cut's length left where it is — whichever cut the session
/// stands in, and nothing the session stands on moves.
void main() {
  const a = CutId('a');
  const b = CutId('b');

  Layer conte(String cut, int duration) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: [
      Frame(id: FrameId('$cut-panel'), duration: duration, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: duration),
    },
  );

  Layer rider(
    String cut, {
    required Map<int, TimelineExposure> timeline,
    AttachedMode mode = AttachedMode.free,
  }) => Layer(
    id: LayerId('$cut-over'),
    name: 'Over',
    kind: LayerKind.storyboard,
    attachedToLayerId: LayerId('$cut-conte'),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: mode,
    frames: [
      for (final entry in timeline.values)
        Frame(id: entry.frameId!, duration: 1, strokes: const []),
    ],
    timeline: timeline,
  );

  /// Cut `a` (12 frames) holds a rider of two glued blocks; cut `b` (20
  /// frames) one whose block holds to the cut's end — a ghost, derived to
  /// the cut it is in.
  EditorSessionManager sessionOf({AttachedMode modeInB = AttachedMode.free}) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('strip-grips'),
        name: 'Strip grips',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              Cut(
                id: a,
                name: 'a',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  conte('a', 12),
                  rider(
                    'a',
                    timeline: const {
                      0: TimelineExposure.drawing(FrameId('a-1'), length: 4),
                      4: TimelineExposure.drawing(FrameId('a-2'), length: 4),
                    },
                  ),
                ],
              ),
              Cut(
                id: b,
                name: 'b',
                duration: 20,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  conte('b', 20),
                  rider(
                    'b',
                    mode: modeInB,
                    timeline: const {
                      2: TimelineExposure.drawing(
                        FrameId('b-1'),
                        length: 4,
                        endEdge: holdMark,
                      ),
                    },
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

  Layer rowOf(EditorSessionManager session, CutId cut, String id) => session
      .repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((candidate) => candidate.id == cut)
      .layers
      .firstWhere((layer) => layer.id == LayerId(id));

  /// The row's blocks as `start+length`, a derived ghost marked `~`.
  List<String> blocksOf(Layer row) => [
    for (final entry in row.timeline.entries)
      '${entry.key}+${entry.value.length}${entry.value.ghost ? '~' : ''}',
  ];

  int durationOf(EditorSessionManager session, CutId cut) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((candidate) => candidate.id == cut)
      .duration;

  test('the fixture: the session stands in cut a, and cut b\'s block holds '
      'to its own cut\'s end', () {
    final session = sessionOf();
    expect(session.activeCutOrNull?.id, a);
    expect(blocksOf(rowOf(session, a, 'a-over')), ['0+4', '4+4']);
    expect(blocksOf(rowOf(session, b, 'b-over')), ['2+4', '6+14~']);
  });

  test('🚨either edge re-times the block as its grip on the timeline does, '
      'and the cut keeps its length', () {
    for (final (:start, :edge, :delta) in const [
      (start: 0, edge: TimelineBlockEdge.end, delta: 2),
      (start: 4, edge: TimelineBlockEdge.end, delta: -2),
      (start: 4, edge: TimelineBlockEdge.start, delta: 1),
      (start: 0, edge: TimelineBlockEdge.start, delta: 2),
    ]) {
      final why = '$edge of the block at $start, by $delta';
      final onStrip = sessionOf();
      expect(
        onStrip.edgeDrag.beginStripRowEdgeDrag(
          cutId: a,
          layerId: const LayerId('a-over'),
          blockStartIndex: start,
          edge: edge,
        ),
        isTrue,
        reason: why,
      );
      onStrip.edgeDrag.updateCutEdgeDrag(delta);
      onStrip.edgeDrag.endCutEdgeDrag();

      final onTimeline = sessionOf();
      expect(
        onTimeline.edgeDrag.beginExposureEdgeDrag(
          layerId: const LayerId('a-over'),
          blockStartIndex: start,
          edge: edge,
        ),
        isTrue,
        reason: 'fixture — $why',
      );
      onTimeline.edgeDrag.updateExposureEdgeDrag(delta);
      onTimeline.edgeDrag.endExposureEdgeDrag();

      final moved = blocksOf(rowOf(onStrip, a, 'a-over'));
      expect(moved, blocksOf(rowOf(onTimeline, a, 'a-over')), reason: why);
      expect(moved, isNot(['0+4', '4+4']), reason: 'LIVENESS — $why');
      expect(durationOf(onStrip, a), 12, reason: why);
    }
  });

  test('🚨a row of a cut the session is NOT in is re-timed where it is — '
      'the hand shows what the release leaves, and one undo takes it', () {
    final session = sessionOf();
    final standing = (
      cut: session.activeCutOrNull?.id,
      layer: session.activeLayerId,
      frame: session.currentFrameIndex,
    );

    expect(
      session.edgeDrag.beginStripRowEdgeDrag(
        cutId: b,
        layerId: const LayerId('b-over'),
        blockStartIndex: 2,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    session.edgeDrag.updateCutEdgeDrag(3);

    final preview = session.dragPreview.value;
    expect(preview, isA<ExposureEdgeDragPreview>());
    expect(
      blocksOf((preview! as ExposureEdgeDragPreview).previewLayer),
      ['2+7', '9+11~'],
      reason: 'the hold runs to the end of the cut the ROW is in (20), '
          'not of the cut the session stands in (12)',
    );
    expect(
      blocksOf(rowOf(session, b, 'b-over')),
      ['2+4', '6+14~'],
      reason: 'a preview writes nothing',
    );

    session.edgeDrag.endCutEdgeDrag();

    expect(session.dragPreview.value, isNull);
    expect(blocksOf(rowOf(session, b, 'b-over')), ['2+7', '9+11~']);
    expect(durationOf(session, b), 20, reason: 'the cut is the conte\'s');
    expect(
      (
        cut: session.activeCutOrNull?.id,
        layer: session.activeLayerId,
        frame: session.currentFrameIndex,
      ),
      standing,
      reason: 'a grip moves nothing the session stands on',
    );

    session.historyManager.undo();
    expect(blocksOf(rowOf(session, b, 'b-over')), ['2+4', '6+14~']);
  });

  test('a row that owns no timing refuses, and so does a block that is not '
      'there — an in-flight drag is left as it was', () {
    final synced = sessionOf(modeInB: AttachedMode.synced);
    expect(
      synced.edgeDrag.beginStripRowEdgeDrag(
        cutId: b,
        layerId: const LayerId('b-over'),
        blockStartIndex: 2,
        edge: TimelineBlockEdge.end,
      ),
      isFalse,
      reason: 'a synced row: its base\'s grips move both',
    );

    final session = sessionOf();
    expect(
      session.edgeDrag.beginStripRowEdgeDrag(
        cutId: a,
        layerId: const LayerId('a-over'),
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
      reason: 'fixture: a drag in flight',
    );
    for (final (:cut, :layer, :start) in const [
      (cut: b, layer: 'b-over', start: 6), // the derived ghost
      (cut: b, layer: 'b-over', start: 3), // inside a block, not its key
      (cut: b, layer: 'a-over', start: 0), // not a row of that cut
      (cut: CutId('none'), layer: 'a-over', start: 0),
    ]) {
      expect(
        session.edgeDrag.beginStripRowEdgeDrag(
          cutId: cut,
          layerId: LayerId(layer),
          blockStartIndex: start,
          edge: TimelineBlockEdge.end,
        ),
        isFalse,
        reason: '$layer at $start in $cut',
      );
    }
    session.edgeDrag.updateCutEdgeDrag(2);
    session.edgeDrag.endCutEdgeDrag();
    expect(
      blocksOf(rowOf(session, a, 'a-over')),
      ['0+6', '6+4'],
      reason: 'the refused grips voided nothing',
    );
  });
}
