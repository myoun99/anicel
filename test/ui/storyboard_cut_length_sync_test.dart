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

  group('an INNER comma drag keeps the pair together too', () {
    /// The default cut (24) with THREE panels: {0: 5, 5: 15, 20: 4}.
    (EditorSessionManager, LayerId) threePanelScene() {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();
      session.selectFrameIndex(20);
      session.createDrawingAtCurrentFrame();
      final id = storyboardLayerForCut(session.requireActiveCut)!.id;
      expect(rowOf(session, id), {0: 5, 5: 15, 20: 4});
      return (session, id);
    }

    int rowEndOf(EditorSessionManager session, LayerId id) => rowOf(session, id)
        .entries
        .map((entry) => entry.key + entry.value!)
        .reduce((a, b) => a > b ? a : b);

    test('a LEFTWARD inner drag does not pin the duration above the row end', () {
      final (session, storyboardId) = threePanelScene();
      final cutId = session.activeCutId!;
      // The COMMITTED floor here is 21 (last division 20 + 1) and the drag
      // takes the row's end to 10. Reading the floor off the committed row
      // while reading the end off the previewed one made `max()` compare two
      // different rows and pin the duration at 21 — an 11-frame hole that
      // the strip hid and the timeline painted.
      expect(minimumCutDurationFor(session.requireActiveCut), 21);

      session.beginStoryboardCommaDrag(cutId: cutId, blockStartIndex: 5);
      session.updateCutEdgeDrag(-14);
      session.endCutEdgeDrag();

      expect(rowOf(session, storyboardId), {0: 5, 5: 1, 6: 4});
      expect(
        session.requireActiveCut.duration,
        rowEndOf(session, storyboardId),
        reason: 'the cut ends where the row ends — that is the whole rule',
      );
      expect(session.requireActiveCut.duration, 10);
    });

    test('and the NEXT drag does not collapse the cut onto a broken row', () {
      final (session, storyboardId) = threePanelScene();
      final cutId = session.activeCutId!;

      // Step 1 used to commit a desynced pair silently…
      session.beginStoryboardCommaDrag(cutId: cutId, blockStartIndex: 5);
      session.updateCutEdgeDrag(-14);
      session.endCutEdgeDrag();
      final afterFirst = session.requireActiveCut.duration;

      // …and step 2 — the LAST panel's edge, the one the user reached for
      // next — detonated it, snapping the cut down onto the row's real end
      // and shoving every cut behind it.
      session.beginStoryboardCommaDrag(cutId: cutId, blockStartIndex: 6);
      session.updateCutEdgeDrag(2);
      session.endCutEdgeDrag();

      expect(session.requireActiveCut.duration, afterFirst + 2);
      expect(
        session.requireActiveCut.duration,
        rowEndOf(session, storyboardId),
      );
    });

    test('a stored MIDDLE hole cannot survive a repository write', () {
      final (session, storyboardId) = threePanelScene();
      final row = session.layers.firstWhere(
        (layer) => layer.id == storyboardId,
      );

      // Try to store a hole — frames 10..19 belonging to no block. This is
      // the shape a delete, a comma button or a paste used to leave behind,
      // and the one the end-of-row rule cannot see: the strip hides it (its
      // reader runs each cell to the next division) while the timeline,
      // which paints the STORED blocks, shows the gap. Two surfaces
      // disagreeing about a cut neither of them was going to fix.
      session.repository.replaceLayer(
        layer: row.copyWith(
          timeline: {
            0: row.timeline[0]!.copyWith(length: 5),
            5: row.timeline[5]!.copyWith(length: 5),
            20: row.timeline[20]!.copyWith(length: 4),
          },
        ),
      );

      // The WRITE closes it. Covering is a store invariant now, the way it
      // already was for the image row — not something the reader papers over
      // on one surface and not the other.
      expect(rowOf(session, storyboardId), {0: 5, 5: 15, 20: 4});
      expect(session.requireActiveCut.duration, 24);
      final cells = storyboardCoverageCells(
        timeline: session.layers
            .firstWhere((layer) => layer.id == storyboardId)
            .timeline,
        cutDuration: session.requireActiveCut.duration,
      );
      expect(cells.last.endIndexExclusive, session.requireActiveCut.duration);
    });

    test('a division sitting OUTSIDE the cut is refused, not repaired — a '
        'normalization must never lose a drawing', () {
      final (session, storyboardId) = threePanelScene();
      final row = session.layers.firstWhere(
        (layer) => layer.id == storyboardId,
      );
      // The reader drops keys at or past the cut's end, so filling from it
      // would DELETE that panel. The row is left exactly as handed over.
      final stranded = {
        0: row.timeline[0]!.copyWith(length: 5),
        5: row.timeline[5]!.copyWith(length: 5),
        30: row.timeline[20]!.copyWith(length: 4),
      };
      session.repository.replaceLayer(
        layer: row.copyWith(timeline: stranded),
      );

      expect(rowOf(session, storyboardId), {0: 5, 5: 5, 30: 4});
    });
  });
}
