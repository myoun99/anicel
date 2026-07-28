import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// A cut and its storyboard row are ONE thing (feedback #9): the cut ends
/// where the row ends, always. These drive the seams where the two could
/// come apart — an adversarial review reproduced a break at every one of
/// them before these existed.
void main() {
  /// The default project's cut (24 frames) with a storyboard row divided at
  /// frame 5, plus a five-frame block on the first track SE row.
  (EditorSessionManager, LayerId, LayerId, LayerId) scene() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final celId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.addLayerOfKind(LayerKind.storyboard);
    session.selectFrameIndex(5);
    session.createDrawingAtCurrentFrame();
    final storyboardId = storyboardLayerForCut(session.requireActiveCut)!.id;
    final seRow = session.activeTrack.seLayers.first;
    session.repository.replaceLayer(
      layer: seRow.copyWith(
        frames: [
          Frame(id: const FrameId('se-cel'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('se-cel'), length: 5),
        },
      ),
    );
    return (session, storyboardId, celId, seRow.id);
  }

  Map<int, int?> rowOf(EditorSessionManager session, LayerId id) => session
      .layers
      .firstWhere((layer) => layer.id == id)
      .timeline
      .map((key, value) => MapEntry(key, value.length));

  /// Drags [anchorId]'s block-0 END comma by [delta] with the selection
  /// spanning down to the storyboard row.
  void dragBulkTo(
    EditorSessionManager session, {
    required LayerId anchorId,
    required LayerId storyboardId,
    required int delta,
  }) {
    session.updateFrameRangeSelectionDrag(
      layerId: anchorId,
      anchorIndex: 0,
      headIndex: 4,
      headLayerId: storyboardId,
    );
    expect(
      session.beginExposureEdgeDrag(
        layerId: anchorId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    session.updateExposureEdgeDrag(delta);
    session.endExposureEdgeDrag();
  }

  group('a bulk retime that reaches the storyboard row moves the cut too', () {
    test('the ANCHOR row\'s kind does not decide it — an SE-anchored bulk '
        'syncs exactly like a drawing-anchored one', () {
      final (seSession, seStoryboardId, _, seId) = scene();
      dragBulkTo(
        seSession,
        anchorId: seId,
        storyboardId: seStoryboardId,
        delta: 3,
      );

      final (celSession, celStoryboardId, celId, _) = scene();
      // The default cel row starts EMPTY, so give it the block the SE row
      // already has — otherwise there is no comma on it to grab.
      celSession.selectLayer(celId);
      celSession.selectFrameIndex(0);
      celSession.createDrawingAtCurrentFrame();
      dragBulkTo(
        celSession,
        anchorId: celId,
        storyboardId: celStoryboardId,
        delta: 3,
      );

      // The storyboard row grew the same way on both, so the cut must have
      // too. Anchoring on the SE row used to leave the cut at 24 while the
      // row ended at 27 — a drawing outside its cut.
      expect(rowOf(seSession, seStoryboardId), {0: 8, 8: 19});
      expect(seSession.requireActiveCut.duration, 27);
      expect(
        seSession.requireActiveCut.duration,
        celSession.requireActiveCut.duration,
      );
    });

    test('the cut never ends before its own last division, however big the '
        'drag', () {
      final (session, storyboardId, _, seId) = scene();

      dragBulkTo(
        session,
        anchorId: seId,
        storyboardId: storyboardId,
        delta: 20,
      );

      final cut = session.requireActiveCut;
      // The row now reads {0: 25, 25: 19}: without the sync the cut stayed
      // at 24, which put the second panel's division AT the cut end — the
      // conte silently dropped that panel while the data stayed real.
      expect(cut.duration, 44);
      expect(cut.duration, greaterThanOrEqualTo(minimumCutDurationFor(cut)));
      expect(
        storyboardCoverageCells(
          timeline: storyboardLayerForCut(cut)!.timeline,
          cutDuration: cut.duration,
        ),
        hasLength(2),
        reason: 'both panels still make a cell',
      );
    });
  });

  group('the cut ends where the row ends', () {
    test('a last-comma shrink takes the cut down with it and stops at the '
        'last division', () {
      final (session, storyboardId, _, _) = scene();
      final cutId = session.activeCutId!;

      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end);
      session.updateCutEdgeDrag(-100);
      session.endCutEdgeDrag();

      final cut = session.requireActiveCut;
      expect(rowOf(session, storyboardId), {0: 5, 5: 1});
      expect(cut.duration, 6);
      expect(cut.duration, minimumCutDurationFor(cut));
    });

    test('a row whose stored end already disagrees with the cut is brought '
        'back onto it, not further off', () {
      final (session, storyboardId, _, _) = scene();
      final cutId = session.activeCutId!;
      // Force the pair apart the way an older file could have it: the row
      // ends at 30 while the cut is still 24.
      session.repository.replaceLayer(
        layer: session.layers
            .firstWhere((layer) => layer.id == storyboardId)
            .copyWith(
              timeline: {
                0: TimelineExposure.drawing(
                  storyboardLayerForCut(
                    session.requireActiveCut,
                  )!.timeline[0]!.frameId!,
                  length: 5,
                ),
                5: TimelineExposure.drawing(
                  storyboardLayerForCut(
                    session.requireActiveCut,
                  )!.timeline[5]!.frameId!,
                  length: 25,
                ),
              },
            ),
      );
      expect(session.requireActiveCut.duration, 24);

      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end);
      session.updateCutEdgeDrag(-4);
      session.endCutEdgeDrag();

      // Deriving the duration from a DELTA would have taken 24 down to 20
      // while the row still ended at 26. The cut lands ON the row's end.
      final cut = session.requireActiveCut;
      final rowEnd = rowOf(session, storyboardId).entries
          .map((entry) => entry.key + entry.value!)
          .reduce((a, b) => a > b ? a : b);
      expect(cut.duration, rowEnd);
      expect(cut.duration, greaterThanOrEqualTo(minimumCutDurationFor(cut)));
    });
  });
}
