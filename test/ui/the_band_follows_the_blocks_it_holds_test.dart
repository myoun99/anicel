import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// F-619 — THE BAND FOLLOWS THE BLOCKS IT HOLDS, whatever edit acting on it
/// moved them.
///
/// 유저 2026-11-18: 「프레임블록 선택하고 코마같은거 일괄조작할때
/// 선택범위ui 사각형이 제대로 안따라감. 예를들어 여러블록 선택하고 뒤엣지
/// 코마 늘린다던가. 다른 경우 포함해서 법 통일해서 따라가게. 뭐는 따라가고
/// 뭐는 안따라가는거같은데」.
///
/// The comma buttons re-snapped the band's end; an edge dragged inside the
/// band, a "+" added to its runs and a merge of its blocks left it where it
/// stood, and a conte comma let it go with the cut's refresh. Each case
/// below drives the verb a press drives and reads the band back — during
/// the drag as well as after it, since the rectangle is painted from the
/// band alone.
void main() {
  /// The default project's cut with its animation row drawn at [frames],
  /// one frame each, and stood on.
  (EditorSessionManager, LayerId) drawnAt(List<int> frames) {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final rowId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(rowId);
    for (final frame in frames) {
      session.selectFrameIndex(frame);
      session.createDrawingAtCurrentFrame();
    }
    expect(
      rowOf(session, rowId),
      {for (final frame in frames) frame: 1},
      reason: 'fixture',
    );
    return (session, rowId);
  }

  /// Drawn on ones at frames 0–3 — one run of four blocks.
  (EditorSessionManager, LayerId) onOnes() => drawnAt([0, 1, 2, 3]);

  /// The default project's cut (24 frames) with a conte row divided at
  /// frame 5 — {0: 5, 5: 19} — whose end is the cut's.
  (EditorSessionManager, LayerId) conteDividedAtFive() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    session.selectFrameIndex(5);
    session.createDrawingAtCurrentFrame();
    final conteId = storyboardLayerForCut(session.requireActiveCut)!.id;
    expect(rowOf(session, conteId), {0: 5, 5: 19}, reason: 'fixture');
    expect(session.requireActiveCut.duration, 24, reason: 'fixture');
    return (session, conteId);
  }

  void sweep(EditorSessionManager session, LayerId rowId, int from, int to) =>
      session.updateFrameRangeSelectionDrag(
        layerId: rowId,
        anchorIndex: from,
        headIndex: to,
      );

  (int, int)? band(EditorSessionManager session) =>
      switch (session.frameRangeSelection.value) {
        null => null,
        final band => (band.startIndex, band.endIndexExclusive),
      };

  group('an edge dragged inside the band', () {
    test('🚨the END edge of many blocks: the band follows each step and the '
        'release', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 0, 3);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 2,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(1);
      expect(rowOf(session, rowId), {0: 1, 1: 1, 2: 1, 3: 1});
      expect(band(session), (0, 8), reason: 'live, over the preview');

      session.edgeDrag.endExposureEdgeDrag();
      expect(rowOf(session, rowId), {0: 2, 2: 2, 4: 2, 6: 2});
      expect(band(session), (0, 8));
    });

    test('the END edge of the band\'s one block follows as many would — the '
        'count picks the retime, never whether the band follows', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 1, 1);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 1,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(2);
      expect(band(session), (1, 4), reason: 'live');
      session.edgeDrag.endExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 1, 1: 3, 4: 1, 5: 1});
      expect(band(session), (1, 4));
    });

    test('the LEAD edge moves the band\'s start with its first block', () {
      final (session, rowId) = drawnAt([0, 4]);
      sweep(session, rowId, 4, 4);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 4,
        edge: TimelineBlockEdge.start,
      );
      session.edgeDrag.updateExposureEdgeDrag(-2);
      expect(band(session), (2, 5), reason: 'live');
      session.edgeDrag.endExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 1, 2: 3});
      expect(band(session), (2, 5));
    });

    test('the LEAD edge of the band\'s later block leaves its start where '
        'the first block stands', () {
      final (session, rowId) = drawnAt([0, 4]);
      sweep(session, rowId, 0, 4);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 4,
        edge: TimelineBlockEdge.start,
      );
      session.edgeDrag.updateExposureEdgeDrag(-2);
      session.edgeDrag.endExposureEdgeDrag();

      expect(band(session)!.$1, 0);
      expect(band(session)!.$2, 5);
    });

    test('a band over two rows ends where the later of their blocks ends', () {
      final (session, rowId) = onOnes();
      session.layerStack.addLayerOfKind(LayerKind.animation);
      final otherId = session.activeLayerId!;
      expect(otherId, isNot(rowId), reason: 'fixture');
      for (final frame in [0, 1]) {
        session.selectFrameIndex(frame);
        session.createDrawingAtCurrentFrame();
      }
      session.updateFrameRangeSelectionDrag(
        layerId: rowId,
        anchorIndex: 0,
        headIndex: 3,
        spanRows: [LayerRowAddress(rowId), LayerRowAddress(otherId)],
      );
      expect(band(session), (0, 4), reason: 'fixture');

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: otherId,
        blockStartIndex: 1,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(1);
      session.edgeDrag.endExposureEdgeDrag();

      final other = rowOf(session, otherId);
      expect(other.values, everyElement(2), reason: 'retimed with the band');
      expect(other.keys.last + 2, lessThan(8), reason: 'the shorter row');
      expect(rowOf(session, rowId), {0: 2, 2: 2, 4: 2, 6: 2});
      expect(band(session), (0, 8), reason: 'the longer row decides');
    });

    test('a drag let go of puts the band back as it was found', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 0, 3);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 2,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(1);
      session.edgeDrag.cancelExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 1, 1: 1, 2: 1, 3: 1});
      expect(band(session), (0, 4));
    });

    test('a step back to no change shows the band where it stood', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 0, 3);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 2,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(1);
      session.edgeDrag.updateExposureEdgeDrag(0);

      expect(band(session), (0, 4));
      session.edgeDrag.endExposureEdgeDrag();
      expect(band(session), (0, 4));
    });

    test('🚨the conte row\'s edge moves its cut, and the band follows past '
        'the cut\'s refresh', () {
      final (session, conteId) = conteDividedAtFive();
      sweep(session, conteId, 0, 4);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: conteId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(3);
      session.edgeDrag.endExposureEdgeDrag();

      expect(rowOf(session, conteId), {0: 8, 8: 19});
      expect(session.requireActiveCut.duration, 27, reason: 'the cut moved');
      expect(band(session), (0, 8));
    });

    // F-619-Q1 asks whether a band should follow its blocks when an edit
    // OUTSIDE it shoves them; until it is answered the band is held only
    // by the edits acting on it.
    test('an edge outside the band holds no band — it stands where it stood',
        () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 2, 3);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(1);
      session.edgeDrag.endExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 2, 2: 1, 3: 1, 4: 1});
      expect(band(session), (2, 4));
    });
  });

  group('the comma buttons', () {
    test('the band\'s blocks set to twos: the band ends where they do', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 0, 3);

      session.exposureVerbs.setCommaOn(
        session.rangeSelections.selectionBlockStartsByLayer()!,
        2,
      );

      expect(rowOf(session, rowId), {0: 2, 2: 2, 4: 2, 6: 2});
      expect(band(session), (0, 8));
    });

    test('🚨a band over the conte row follows the comma that moves its cut — '
        'the cut\'s refresh let it go', () {
      final (session, conteId) = conteDividedAtFive();
      sweep(session, conteId, 0, 4);

      session.exposureVerbs.setCommaOn(
        session.rangeSelections.selectionBlockStartsByLayer()!,
        8,
      );

      expect(rowOf(session, conteId), {0: 8, 8: 19});
      expect(session.requireActiveCut.duration, 27, reason: 'the cut moved');
      expect(band(session), (0, 8));
    });
  });

  group('the "+" on a run the band holds', () {
    test('the band grows over the frames its run gains, live and on '
        'release', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 0, 3);

      session.runFramesAdd.beginRunFramesAddDrag(
        layerId: rowId,
        blockStartIndex: 0,
        atEnd: true,
      );
      session.runFramesAdd.updateRunFramesAddDrag(2);
      expect(band(session), (0, 6), reason: 'live');
      session.runFramesAdd.endRunFramesAddDrag();

      expect(rowOf(session, rowId).length, 6);
      expect(band(session), (0, 6));
    });

    test('a "+" let go of puts the band back', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 0, 3);

      session.runFramesAdd.beginRunFramesAddDrag(
        layerId: rowId,
        blockStartIndex: 0,
        atEnd: true,
      );
      session.runFramesAdd.updateRunFramesAddDrag(2);
      session.runFramesAdd.cancelRunFramesAddDrag();

      expect(band(session), (0, 4));
    });

    // F-619-Q1, as the edge's twin above.
    test('a "+" on a run outside the band holds no band', () {
      final (session, rowId) = drawnAt([0, 3, 4]);
      sweep(session, rowId, 3, 4);

      session.runFramesAdd.beginRunFramesAddDrag(
        layerId: rowId,
        blockStartIndex: 0,
        atEnd: true,
      );
      session.runFramesAdd.updateRunFramesAddDrag(3);
      session.runFramesAdd.endRunFramesAddDrag();

      expect(rowOf(session, rowId).keys.last, 5, reason: 'its blocks moved');
      expect(band(session), (3, 5));
    });
  });

  test('the band\'s blocks merged: the band stays over the block they make',
      () {
    final (session, rowId) = onOnes();
    sweep(session, rowId, 0, 3);

    final plan = session.layerMerging.planOfBand();
    expect(plan, isNotNull, reason: 'fixture: the band merges');
    expect(session.layerMerging.landBlocks(plan!), isTrue);

    expect(rowOf(session, rowId), {0: 4});
    expect(band(session), (0, 4));
  });
}

Map<int, int?> rowOf(EditorSessionManager session, LayerId id) => session
    .layers
    .firstWhere((layer) => layer.id == id)
    .timeline
    .map((key, value) => MapEntry(key, value.length));
