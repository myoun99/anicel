import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart' show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// PEN-8 #2: drawing navigation walks BLOCKS where blocks exist and
/// falls back to ONE-FRAME steps through empty space — the plain-arrow/
/// 파라파라 unit never dead-ends.
///
/// R10 #13 generalized the subject without touching that walk: whatever
/// the current ROW is, the flip counts THAT row's blocks.
void main() {
  EditorSessionManager sessionWithBlock() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final cut = session.requireActiveCut;
    final layer = cut.layers.first;
    session.repository.replaceLayer(
      layer: layer.copyWith(
        frames: [
          Frame(id: const FrameId('nav-f1'), duration: 1, strokes: const []),
        ],
        timeline: {
          2: const TimelineExposure.drawing(FrameId('nav-f1'), length: 3),
        },
      ),
    );
    session.selectLayer(layer.id);
    return session;
  }

  test('next: one COLUMN a press — empty frames one at a time, a block '
      'whole however long it holds', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(0);
    session.frameVerbs.flipRow(forward: true);
    expect(session.currentFrameIndex, 1, reason: 'an empty frame is a column');

    session.frameVerbs.flipRow(forward: true);
    expect(session.currentFrameIndex, 2, reason: 'onto the block');

    // The block holds 2..4 and is ONE column: the next press leaves the
    // whole run, landing where it ends.
    session.frameVerbs.flipRow(forward: true);
    expect(session.currentFrameIndex, 5, reason: 'the block ends here');

    session.frameVerbs.flipRow(forward: true);
    expect(session.currentFrameIndex, 6);

    // From INSIDE the block the same column is left in one press: a hold
    // belongs to its block, not to columns of its own.
    session.selectFrameIndex(3);
    session.frameVerbs.flipRow(forward: true);
    expect(session.currentFrameIndex, 5, reason: 'mid-block leaves whole');
  });

  test('previous: the same columns, walked back — this is the direction '
      'that used to skip the empty space entirely', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(7);
    session.frameVerbs.flipRow(forward: false);
    expect(session.currentFrameIndex, 6);
    session.frameVerbs.flipRow(forward: false);
    expect(session.currentFrameIndex, 5);

    // The frame after a block ends steps back to that block's HEAD — it
    // used to jump here from far away, skipping 5 and 6 on the way.
    session.frameVerbs.flipRow(forward: false);
    expect(session.currentFrameIndex, 2, reason: 'the block head');

    // Before the block, empty frames again, one column each.
    session.frameVerbs.flipRow(forward: false);
    expect(session.currentFrameIndex, 1);
    session.frameVerbs.flipRow(forward: false);
    expect(session.currentFrameIndex, 0);
    session.frameVerbs.flipRow(forward: false);
    expect(
      session.currentFrameIndex,
      0,
      reason: 'the start of the film is the one real floor',
    );
  });

  test('★ the two directions are the same sentence: walking right and '
      'back left visits the same columns', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(0);
    final forward = <int>[0];
    for (var press = 0; press < 4; press += 1) {
      session.frameVerbs.flipRow(forward: true);
      forward.add(session.currentFrameIndex);
    }
    expect(forward, [0, 1, 2, 5, 6]);

    final backward = <int>[];
    for (var press = 0; press < 4; press += 1) {
      session.frameVerbs.flipRow(forward: false);
      backward.add(session.currentFrameIndex);
    }
    expect(backward, forward.reversed.skip(1));
  });

  group('R10 #13: the flip counts the CURRENT ROW\'s blocks', () {
    /// One track, three cuts of 12 frames — the film's own blocks.
    EditorSessionManager threeCutSession() {
      final project = Project(
        id: const ProjectId('p-three-cuts'),
        name: 'Three Cuts',
        createdAt: DateTime.utc(2026, 7, 31),
        tracks: [
          Track(
            id: const TrackId('default-track'),
            name: 'Video Track',
            cuts: [
              for (var index = 1; index <= 3; index += 1)
                createDefaultCut(
                  cutId: CutId('cut-$index'),
                  name: '$index',
                  layerId: LayerId('layer-$index'),
                ),
            ],
          ),
        ],
      );
      return EditorSessionManager(initialProject: project);
    }

    test('the row defaults to the LAYER you draw on, not the track — the '
        'flip a session opens with is the 파라파라 one', () {
      final session = sessionWithBlock();
      addTearDown(session.dispose);

      expect(session.currentRow, isA<LayerRowAddress>());
    });

    test('on a V row the blocks are CUTS, so the flip crosses cut '
        'boundaries — the only place it ever does', () {
      final session = threeCutSession();
      addTearDown(session.dispose);
      expect(session.activeCutId, const CutId('cut-1'));

      session.selectTrackRow(const TrackId('default-track'));
      expect(session.currentRow, isA<TrackRowAddress>());

      session.frameVerbs.flipRow(forward: true);
      expect(session.activeCutId, const CutId('cut-2'));
      expect(session.currentFrameIndex, 0, reason: 'the cut block\'s start');

      session.frameVerbs.flipRow(forward: true);
      expect(session.activeCutId, const CutId('cut-3'));

      // Mid-cut, backwards leaves this cut's column whole — a hold and
      // its head are ONE column, so stepping back from either lands on
      // the previous cut rather than restarting this one.
      session.selectFrameIndex(5);
      session.frameVerbs.flipRow(forward: false);
      expect(session.activeCutId, const CutId('cut-2'));
      expect(session.currentFrameIndex, 0, reason: 'that cut block\'s start');
    });

    test('past the last cut a V row walks ONE frame — "a block where there '
        'are blocks, a frame where there are none"', () {
      final session = threeCutSession();
      addTearDown(session.dispose);
      session.selectTrackRow(const TrackId('default-track'));

      // Onto the last cut, then to its final frame.
      session.frameVerbs.flipRow(forward: true);
      session.frameVerbs.flipRow(forward: true);
      expect(session.activeCutId, const CutId('cut-3'));
      final duration = session.requireActiveCut.duration;
      session.selectFrameIndex(duration - 1);

      final globalBefore = session.editingGlobalFrame;
      session.frameVerbs.flipRow(forward: true);
      expect(
        session.editingGlobalFrame,
        globalBefore + 1,
        reason: 'one frame past the film, which parks',
      );
    });

    /// The same three cuts with EMPTY FRAMES between them — cut 2 and 3
    /// each carry a leading gap.
    EditorSessionManager gappedCutSession() {
      final project = Project(
        id: const ProjectId('p-gapped-cuts'),
        name: 'Gapped Cuts',
        createdAt: DateTime.utc(2026, 8, 5),
        tracks: [
          Track(
            id: const TrackId('default-track'),
            name: 'Video Track',
            cuts: [
              for (var index = 1; index <= 3; index += 1)
                createDefaultCut(
                  cutId: CutId('cut-$index'),
                  name: '$index',
                  layerId: LayerId('layer-$index'),
                ).copyWith(leadingGapFrames: index == 1 ? 0 : 3),
            ],
          ),
        ],
      );
      return EditorSessionManager(initialProject: project);
    }

    test('★ a LAYER row keeps walking its OWN axis past the cut end — it '
        'never leaves the row it is flipping', () {
      // The timeline's frame axis is endless: it papers what has been
      // scrolled into existence and dims the cells past the cut end. So
      // rightwards never runs out WITHOUT the flip changing rows, which
      // is the point — handing the landing to the track would drop the
      // layer being flipped.
      final session = gappedCutSession();
      addTearDown(session.dispose);
      expect(session.currentRow, isA<LayerRowAddress>());

      final duration = session.requireActiveCut.duration;
      session.selectFrameIndex(duration - 1);

      for (var press = 1; press <= 3; press += 1) {
        session.frameVerbs.flipRow(forward: true);
        expect(session.currentFrameIndex, duration - 1 + press);
        expect(
          session.activeCutId,
          const CutId('cut-1'),
          reason: 'still the same cut, still the same row',
        );
      }

      // And back down the same cells.
      session.frameVerbs.flipRow(forward: false);
      expect(session.currentFrameIndex, duration + 1);
      expect(session.activeCutId, const CutId('cut-1'));
    });

    test('★ leftwards the cut\'s own start is the floor — a layer row does '
        'not fall out of the front of its cut either', () {
      final session = gappedCutSession();
      addTearDown(session.dispose);

      session.selectCut(const CutId('cut-2'));
      expect(session.currentRow, isA<LayerRowAddress>());
      session.selectFrameIndex(0);

      session.frameVerbs.flipRow(forward: false);
      expect(session.currentFrameIndex, 0);
      expect(
        session.activeCutId,
        const CutId('cut-2'),
        reason: 'the gap before this cut belongs to the V row, not to this one',
      );
    });

    test('★ a V row DOES cross, and lands on the row that cut was last '
        'worked on', () {
      final session = gappedCutSession();
      addTearDown(session.dispose);

      // Visit cut 2 and leave it on a SECOND layer.
      session.selectCut(const CutId('cut-2'));
      session.layerStack.addLayerOfKind(LayerKind.animation);
      final rememberedRow = session.activeLayerId;
      expect(rememberedRow, isNot(const LayerId('layer-2')));

      // Back to cut 1, then walk the TRACK across the gap into cut 2.
      session.selectCut(const CutId('cut-1'));
      session.selectTrackRow(const TrackId('default-track'));
      final duration = session.requireActiveCut.duration;
      session.selectFrameIndex(duration - 1);

      // A gap is frames on both panels alike, so the crossing costs a
      // press per frame rather than teleporting to the next cut.
      session.frameVerbs.flipRow(forward: true);
      expect(session.activeCutId, isNull, reason: 'parked in the gap');
      expect(session.editingGlobalFrame, duration);
      session.frameVerbs.flipRow(forward: true);
      expect(session.editingGlobalFrame, duration + 1);
      session.frameVerbs.flipRow(forward: true);
      expect(session.editingGlobalFrame, duration + 2);

      session.frameVerbs.flipRow(forward: true);
      expect(session.activeCutId, const CutId('cut-2'));
      expect(
        session.activeLayerId,
        rememberedRow,
        reason:
            'the cut comes back on the row it was last worked on — not on '
            'the row the flip arrived from',
      );
    });

    test('picking a layer moves THE row back, so the flip returns to that '
        'layer\'s blocks', () {
      final session = threeCutSession();
      addTearDown(session.dispose);

      session.selectTrackRow(const TrackId('default-track'));
      expect(session.currentRow, isA<TrackRowAddress>());

      final layerId = session.requireActiveCut.layers.first.id;
      session.selectLayer(layerId);

      expect(session.currentRow, LayerRowAddress(layerId));
      final cutBefore = session.activeCutId;
      session.frameVerbs.flipRow(forward: true);
      expect(
        session.activeCutId,
        cutBefore,
        reason:
            'a layer row lives inside one cut — that is why "which row '
            'of the next cut do I land on" never gets asked',
      );
    });
  });

  // 🗣️F-245 (유저 2026-10-01, 「그게 아님」): 「1(홀드)---- 일경우 1에
  // 서있을때 오른쪽 플립하면 두번째인 - 로 이동되는건 좋음. 근데 그 다음
  // 플립에서도 세번째 -, 네번째 -으로 이동되야한단거임. 일반 1프레임이동이랑
  // 똑같이. 즉 리피트는 고스트프레임을 블록으로 인식해서 걸어가지만 홀드는
  // 빈공간으로 인식해서 플립이 1프레임마다」 — a HOLD is empty space to the
  // flip, a REPEAT's ghost a column. ↩️The 09-30 reading made the hold one
  // column of its own; ↩️A7① (2026-08-18) had merged it into the held run.
  group('a HOLD is walked a frame at a time, a REPEAT a part at a time', () {
    (EditorSessionManager, LayerId) heldSession(
      TimelineRunEdgeMode mode, {
      int blockLength = 1,
    }) {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      s.createDrawingAtCurrentFrame(); // 1-cell block at index 0
      final layerId = s.activeLayer!.id;
      if (blockLength > 1) {
        s.edgeDrag.beginExposureEdgeDrag(
          layerId: layerId,
          blockStartIndex: 0,
          edge: TimelineBlockEdge.end,
        );
        s.edgeDrag.updateExposureEdgeDrag(blockLength - 1);
        s.edgeDrag.endExposureEdgeDrag();
      }
      s.rangeMove.setRunEdgeBehavior(
        layerId: layerId,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
        mode: mode,
      );
      return (s, layerId);
    }

    test('forward from the held block steps onto every cell of the hold, '
        'one at a time, and then out of it', () {
      final (s, _) = heldSession(TimelineRunEdgeMode.hold);
      addTearDown(s.dispose);
      final cutEnd = s.requireActiveCut.duration;
      expect(cutEnd, greaterThan(3), reason: 'fixture: a hold to walk');

      s.selectFrameIndex(0);
      for (var frame = 1; frame <= cutEnd; frame += 1) {
        s.frameVerbs.flipRow(forward: true);
        expect(
          s.currentFrameIndex,
          frame,
          reason: '「일반 1프레임이동이랑 똑같이」',
        );
      }
    });

    test('backward through the hold is the same walk, onto the held block '
        'at the end', () {
      final (s, _) = heldSession(TimelineRunEdgeMode.hold);
      addTearDown(s.dispose);
      final cutEnd = s.requireActiveCut.duration;

      s.selectFrameIndex(cutEnd);
      for (var frame = cutEnd - 1; frame >= 0; frame -= 1) {
        s.frameVerbs.flipRow(forward: false);
        expect(s.currentFrameIndex, frame);
      }
    });

    test('a REPEAT\'s parts are walked as blocks, as they were', () {
      final (s, _) = heldSession(TimelineRunEdgeMode.repeat, blockLength: 2);
      addTearDown(s.dispose);
      expect(
        s.activeLayer!.timeline[0]?.length,
        2,
        reason: 'fixture: a two-cell block, so a part and a cell differ',
      );

      s.selectFrameIndex(0);
      s.frameVerbs.flipRow(forward: true);
      expect(s.currentFrameIndex, 2, reason: 'onto the first part');
      s.frameVerbs.flipRow(forward: true);
      expect(
        s.currentFrameIndex,
        4,
        reason: 'each repeated part is a flip column of its own',
      );
    });
  });
}
