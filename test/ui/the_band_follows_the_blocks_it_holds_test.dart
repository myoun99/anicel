import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart'
    show rederiveRunBehaviors;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_preset_sync.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

import '../helpers/a_cut_with_a_drawing_row.dart';

/// F-619 — THE BAND FOLLOWS THE BLOCKS IT HOLDS, whatever edit moved them:
/// one acting on it, or one beside it (F-619-Q1).
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
  // A sound's name tag is measured as its row is laid, through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('🚨the LEAD edge of the band\'s last block pulled back thins the '
        'band out — its first block runs on over the one that went — and '
        'the band ends where that first block now ends', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 1, 2);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 2,
        edge: TimelineBlockEdge.start,
      );
      session.edgeDrag.updateExposureEdgeDrag(2);
      expect(band(session), (1, 3), reason: 'live');
      session.edgeDrag.endExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 1, 1: 2, 3: 1}, reason: 'I-179-Q1');
      expect(band(session), (1, 3));
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

  /// 🗣️F-619-Q1 (유저 2026-11-19): 「따라간다 — 어떤 조작이든 선택한 블록이
  /// 움직이면」. An edit BESIDE the band that moves the blocks it holds moves
  /// the band with them, during a drag as well as after it. ↩️It stood where
  /// it was swept, over the blocks pushed into its place.
  group('an edit beside the band moves its blocks', () {
    test('🚨the END edge of a block in front pushes them: the band follows, '
        'each step and the release', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 2, 3);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(1);
      expect(band(session), (3, 5), reason: 'live, over the preview');
      session.edgeDrag.endExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 2, 2: 1, 3: 1, 4: 1});
      expect(band(session), (3, 5));
    });

    test('a drag in front let go of puts the band back', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 2, 3);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(2);
      session.edgeDrag.cancelExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 1, 1: 1, 2: 1, 3: 1});
      expect(band(session), (2, 4));
    });

    test('the LEAD edge of the block in front, pulled back past it over the '
        'first of them, leaves the band over what is left of them', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 2, 3);

      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: 1,
        edge: TimelineBlockEdge.start,
      );
      session.edgeDrag.updateExposureEdgeDrag(2);
      expect(band(session), (3, 4), reason: 'live');
      session.edgeDrag.endExposureEdgeDrag();

      expect(rowOf(session, rowId), {0: 3, 3: 1}, reason: 'I-179');
      expect(band(session), (3, 4));
    });

    test('a "+" at the end of the run in front pushes them: the band '
        'follows, live and on release', () {
      final (session, rowId) = drawnAt([0, 3, 4]);
      sweep(session, rowId, 3, 4);

      session.runFramesAdd.beginRunFramesAddDrag(
        layerId: rowId,
        blockStartIndex: 0,
        atEnd: true,
      );
      session.runFramesAdd.updateRunFramesAddDrag(3);
      expect(band(session), (4, 6), reason: 'live');
      session.runFramesAdd.endRunFramesAddDrag();

      expect(rowOf(session, rowId).keys.last, 5, reason: 'its blocks moved');
      expect(band(session), (4, 6));
    });

    test('🚨the same new blocks, two answers: a "+" at the end of the run in '
        'front leaves the band over its own blocks, a "+" at the head of the '
        'band\'s run takes them in', () {
      final (beside, besideRow) = drawnAt([0, 3, 4]);
      sweep(beside, besideRow, 3, 4);
      beside.runFramesAdd.beginRunFramesAddDrag(
        layerId: besideRow,
        blockStartIndex: 0,
        atEnd: true,
      );
      beside.runFramesAdd.updateRunFramesAddDrag(2);
      beside.runFramesAdd.endRunFramesAddDrag();

      final (acting, actingRow) = drawnAt([0, 3, 4]);
      sweep(acting, actingRow, 3, 4);
      acting.runFramesAdd.beginRunFramesAddDrag(
        layerId: actingRow,
        blockStartIndex: 3,
        atEnd: false,
      );
      acting.runFramesAdd.updateRunFramesAddDrag(2);
      acting.runFramesAdd.endRunFramesAddDrag();

      expect(
        rowOf(beside, besideRow),
        {0: 1, 1: 1, 2: 1, 3: 1, 4: 1},
        reason: 'the gap filled, nothing pushed',
      );
      expect(rowOf(acting, actingRow), rowOf(beside, besideRow));
      expect(band(beside), (3, 5));
      expect(band(acting), (1, 5));
    });

    test('a new drawing at the head of a block in front pushes them', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 2, 3);

      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();

      expect(rowOf(session, rowId), {0: 1, 1: 1, 2: 1, 3: 1, 4: 1});
      expect(band(session), (3, 5));
    });

    test('a strip grip on a block in front pushes them: live and on '
        'release', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 2, 3);

      expect(
        session.edgeDrag.beginStripRowEdgeDrag(
          cutId: session.activeCutId!,
          layerId: rowId,
          blockStartIndex: 0,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );
      session.edgeDrag.updateCutEdgeDrag(1);
      expect(band(session), (3, 5), reason: 'live');
      session.edgeDrag.endCutEdgeDrag();

      expect(rowOf(session, rowId), {0: 2, 2: 1, 3: 1, 4: 1});
      expect(band(session), (3, 5));
    });

    test('🚨the conte strip\'s comma moves its cut, and the band over the '
        'panel after follows it past the cut\'s refresh', () {
      final (session, conteId) = conteDividedAtFive();
      sweep(session, conteId, 5, 23);
      expect(band(session), (5, 24), reason: 'fixture');

      expect(
        session.edgeDrag.beginStoryboardCommaDrag(
          cutId: session.activeCutId!,
          blockStartIndex: 0,
        ),
        isTrue,
      );
      session.edgeDrag.updateCutEdgeDrag(3);
      expect(band(session), (8, 27), reason: 'live');
      session.edgeDrag.endCutEdgeDrag();

      expect(rowOf(session, conteId), {0: 8, 8: 19});
      expect(session.requireActiveCut.duration, 27, reason: 'the cut moved');
      expect(band(session), (8, 27));
    });

    test('the cut\'s end grip on a cut with a conte row is its last comma: '
        'the band over the last panel follows its end, past the cut\'s '
        'refresh', () {
      final (session, conteId) = conteDividedAtFive();
      sweep(session, conteId, 5, 23);

      expect(
        session.edgeDrag.beginCutEdgeDrag(
          cutId: session.activeCutId!,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );
      session.edgeDrag.updateCutEdgeDrag(3);
      expect(band(session), (5, 27), reason: 'live');
      session.edgeDrag.endCutEdgeDrag();

      expect(rowOf(session, conteId), {0: 5, 5: 22});
      expect(band(session), (5, 27));
    });

    group('a cut\'s lead trim re-tiles its conte row', () {
      /// The cut [conteDividedAtFive] makes, its lead edge pulled back
      /// [delta], the band over the panel after the first.
      EditorSessionManager trimmed(int delta) {
        final (session, conteId) = conteDividedAtFive();
        sweep(session, conteId, 5, 23);
        expect(
          session.edgeDrag.beginCutEdgeDrag(
            cutId: session.activeCutId!,
            edge: TimelineBlockEdge.start,
          ),
          isTrue,
        );
        session.edgeDrag.updateCutEdgeDrag(delta);
        return session;
      }

      test('the band follows the panel, live and past the release', () {
        final session = trimmed(2);
        expect(band(session), (3, 22), reason: 'live');
        session.edgeDrag.endCutEdgeDrag();

        final conteId = storyboardLayerForCut(session.requireActiveCut)!.id;
        expect(rowOf(session, conteId), {0: 3, 3: 19});
        expect(band(session), (3, 22));
      });

      test('a step back to no change, or a drag let go of, shows the band '
          'where it was swept', () {
        final session = trimmed(2);
        session.edgeDrag.updateCutEdgeDrag(0);
        expect(band(session), (5, 24));

        session.edgeDrag.updateCutEdgeDrag(2);
        session.edgeDrag.cancelCutEdgeDrag();
        expect(band(session), (5, 24));
      });
    });

    test('a cut\'s trailing trim moves none of its blocks: the band stands '
        'where it stood, past the cut\'s refresh', () {
      final (session, rowId) = onOnes();
      sweep(session, rowId, 0, 3);

      session.edgeDrag.beginCutEdgeDrag(
        cutId: session.activeCutId!,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateCutEdgeDrag(2);
      session.edgeDrag.endCutEdgeDrag();

      expect(session.requireActiveCut.duration, 26, reason: 'the cut moved');
      expect(band(session), (0, 4));
    });

    test('🚨a cut its lead edge sweeps away takes its band with it — never '
        'laid on the cut left open', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      createCutWithADrawingRow(session);
      final cut = session.activeCutId!;
      final rowId = session.activeLayerId!;
      for (final frame in [0, 1]) {
        session.selectFrameIndex(frame);
        session.createDrawingAtCurrentFrame();
      }
      sweep(session, rowId, 0, 1);
      expect(band(session), (0, 2), reason: 'fixture');
      final duration = session.requireActiveCut.duration;

      session.edgeDrag.beginCutEdgeDrag(
        cutId: cut,
        edge: TimelineBlockEdge.start,
      );
      session.edgeDrag.updateCutEdgeDrag(duration + 40);
      session.edgeDrag.endCutEdgeDrag();

      expect(session.cutById(cut), isNull, reason: 'fixture: the cut went');
      expect(session.activeCutId, isNot(cut));
      expect(band(session), isNull);
    });

    group('a band on the track\'s axis', () {
      late EditorSessionManager session;
      late LayerId s1;
      late int cut2;

      setUp(() {
        session = EditorSessionManager(initialProject: createDefaultProject());
        s1 = session.activeTrack.seLayers.first.id;
        createCutWithADrawingRow(session);
        cut2 = session.activeCutGlobalStartFrame;
        expect(cut2, greaterThan(0), reason: 'fixture: a track row\'s keys');
      });
      tearDown(() => session.dispose());

      /// A one-frame sound from [localFrame] of the open cut.
      void placeSound(int localFrame) {
        session.selectLayer(s1);
        session.selectFrameIndex(localFrame);
        session.seEntries.createSeEntryAtCurrentFrame(
          name: 'se$localFrame',
          lengthFrames: 1,
        );
      }

      List<int> soundStarts() => [
        ...session.activeTrack.seLayers
            .firstWhere((layer) => layer.id == s1)
            .timeline
            .keys,
      ];

      (int, int)? trackBand() =>
          switch (session.trackFrameRangeSelection.value) {
            null => null,
            final band => (band.startFrame, band.endFrameExclusive),
          };

      /// Three sounds on ones from the cut's first frame, the band over the
      /// later two.
      void soundsBanded() {
        for (final frame in [0, 1, 2]) {
          placeSound(frame);
        }
        session.rangeSelections.updateTrackRowRangeSelectionByFrame(
          layerId: s1,
          anchorGlobalFrame: cut2 + 1,
          headGlobalFrame: cut2 + 2,
        );
        expect(trackBand(), (cut2 + 1, cut2 + 3), reason: 'fixture');
      }

      test('a sound made at the head of the one in front pushes them', () {
        soundsBanded();

        placeSound(0);

        expect(soundStarts(), [for (var i = 0; i < 4; i += 1) cut2 + i]);
        expect(trackBand(), (cut2 + 2, cut2 + 4));
      });

      test('the storyboard\'s grip on the sound in front — keyed on the '
          'track — pushes them', () {
        soundsBanded();

        session.edgeDrag.beginExposureEdgeDrag(
          layerId: s1,
          blockStartIndex: cut2,
          edge: TimelineBlockEdge.end,
          blockStartIsGlobal: true,
        );
        session.edgeDrag.updateExposureEdgeDrag(1);
        expect(trackBand(), (cut2 + 2, cut2 + 4), reason: 'live');
        session.edgeDrag.endExposureEdgeDrag();

        expect(soundStarts(), [cut2, cut2 + 2, cut2 + 3]);
        expect(trackBand(), (cut2 + 2, cut2 + 4));
      });

      test('a timeline grip on the sound in front pushes them', () {
        soundsBanded();

        session.edgeDrag.beginExposureEdgeDrag(
          layerId: s1,
          blockStartIndex: 0,
          edge: TimelineBlockEdge.end,
        );
        session.edgeDrag.updateExposureEdgeDrag(1);
        expect(trackBand(), (cut2 + 2, cut2 + 4), reason: 'live');
        session.edgeDrag.endExposureEdgeDrag();

        expect(soundStarts(), [cut2, cut2 + 2, cut2 + 3]);
        expect(trackBand(), (cut2 + 2, cut2 + 4));
      });
    });

    test('a sync to the pool\'s preset that lengthens a block pushes the ones '
        'after it, and the band on the track\'s axis over them follows', () {
      final session = EditorSessionManager(initialProject: _soundsOfAClap());
      addTearDown(session.dispose);
      session.trackFrameRangeSelection.value = const TrackFrameRangeSelection(
        trackId: TrackId('t1'),
        anchorRow: LayerRowAddress(LayerId('s1')),
        rows: [LayerRowAddress(LayerId('s1'))],
        startFrame: 12,
        endFrameExclusive: 18,
      );

      final project = session.repository.requireProject();
      session.mediaPool.syncPlaces(
        _clap,
        fields: const {MediaSyncField.length},
        places: syncPlacesOf(
          project,
          project.mediaAssets.single,
          lengths: (sound: 20, pictures: null),
        ),
      );

      expect(
        session.activeTrack.seLayers.single.timeline.map(
          (start, block) => MapEntry(start, block.length),
        ),
        {0: 6, 6: 6, 12: 6, 18: 2},
        reason: 'fixture: the blocks after the first pushed',
      );
      final band = session.trackFrameRangeSelection.value;
      expect((band?.startFrame, band?.endFrameExclusive), (12, 20));
    });
  });
}

const _clap = 'C:/media/clap.wav';

/// One SE row on the default track's one cut, the clap placed by three of
/// its blocks — two showing 「a」, one 「b」 — and 「other」 last, each glued
/// to the next but the first; the pool's preset places the clap six frames
/// long (frames 2 to 7 of it).
Project _soundsOfAClap() => Project(
  id: const ProjectId('band-over-a-synced-row'),
  name: 'Band over a synced row',
  createdAt: DateTime.utc(2026, 11, 19),
  mediaAssets: [
    MediaAsset(
      path: _clap,
      name: 'clap',
      preset: const MediaPreset(inFrame: 2, outFrame: 7),
    ),
  ],
  tracks: [
    Track(
      id: const TrackId('t1'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('c1'),
          name: 'c1',
          duration: 24,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: const [],
        ),
      ],
      seLayers: [
        rederiveRunBehaviors(
          Layer(
            id: const LayerId('s1'),
            name: 's1',
            kind: LayerKind.se,
            frames: [
              for (final id in ['a', 'b', 'other'])
                Frame(id: FrameId(id), duration: 1, strokes: const []),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('a'), length: 4),
              5: const TimelineExposure.drawing(FrameId('a'), length: 4),
              12: const TimelineExposure.drawing(FrameId('b'), length: 3),
              16: const TimelineExposure.drawing(FrameId('other'), length: 2),
            },
            audioClips: [
              AudioClip(filePath: _clap, frameId: const FrameId('a')),
              AudioClip(
                filePath: _clap,
                frameId: const FrameId('b'),
                offsetFrames: 2,
              ),
            ],
          ),
          drawnFrameCount: 24,
        ),
      ],
    ),
  ],
);

Map<int, int?> rowOf(EditorSessionManager session, LayerId id) => session
    .layers
    .firstWhere((layer) => layer.id == id)
    .timeline
    .map((key, value) => MapEntry(key, value.length));
