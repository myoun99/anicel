import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
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
          2: TimelineExposure.drawing(const FrameId('nav-f1'), length: 3),
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
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 1, reason: 'an empty frame is a column');

    session.selectNextDrawing();
    expect(session.currentFrameIndex, 2, reason: 'onto the block');

    // The block holds 2..4 and is ONE column: the next press leaves the
    // whole run, landing where it ends.
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 5, reason: 'the block ends here');

    session.selectNextDrawing();
    expect(session.currentFrameIndex, 6);

    // From INSIDE the block the same column is left in one press: a hold
    // belongs to its block, not to columns of its own.
    session.selectFrameIndex(3);
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 5, reason: 'mid-block leaves whole');
  });

  test('previous: the same columns, walked back — this is the direction '
      'that used to skip the empty space entirely', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(7);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 6);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 5);

    // The frame after a block ends steps back to that block's HEAD — it
    // used to jump here from far away, skipping 5 and 6 on the way.
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 2, reason: 'the block head');

    // Before the block, empty frames again, one column each.
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 1);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 0);
    session.selectPreviousDrawing();
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
      session.selectNextDrawing();
      forward.add(session.currentFrameIndex);
    }
    expect(forward, [0, 1, 2, 5, 6]);

    final backward = <int>[];
    for (var press = 0; press < 4; press += 1) {
      session.selectPreviousDrawing();
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

      session.selectNextDrawing();
      expect(session.activeCutId, const CutId('cut-2'));
      expect(session.currentFrameIndex, 0, reason: 'the cut block\'s start');

      session.selectNextDrawing();
      expect(session.activeCutId, const CutId('cut-3'));

      // Mid-cut, backwards leaves this cut's column whole — a hold and
      // its head are ONE column, so stepping back from either lands on
      // the previous cut rather than restarting this one.
      session.selectFrameIndex(5);
      session.selectPreviousDrawing();
      expect(session.activeCutId, const CutId('cut-2'));
      expect(session.currentFrameIndex, 0, reason: 'that cut block\'s start');
    });

    test('past the last cut a V row walks ONE frame — "a block where there '
        'are blocks, a frame where there are none"', () {
      final session = threeCutSession();
      addTearDown(session.dispose);
      session.selectTrackRow(const TrackId('default-track'));

      // Onto the last cut, then to its final frame.
      session.selectNextDrawing();
      session.selectNextDrawing();
      expect(session.activeCutId, const CutId('cut-3'));
      final duration = session.requireActiveCut.duration;
      session.selectFrameIndex(duration - 1);

      final globalBefore = session.editingGlobalFrame;
      session.selectNextDrawing();
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
        session.selectNextDrawing();
        expect(session.currentFrameIndex, duration - 1 + press);
        expect(
          session.activeCutId,
          const CutId('cut-1'),
          reason: 'still the same cut, still the same row',
        );
      }

      // And back down the same cells.
      session.selectPreviousDrawing();
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

      session.selectPreviousDrawing();
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
      session.addLayerOfKind(LayerKind.animation);
      final rememberedRow = session.activeLayerId;
      expect(rememberedRow, isNot(const LayerId('layer-2')));

      // Back to cut 1, then walk the TRACK across the gap into cut 2.
      session.selectCut(const CutId('cut-1'));
      session.selectTrackRow(const TrackId('default-track'));
      final duration = session.requireActiveCut.duration;
      session.selectFrameIndex(duration - 1);

      // A gap is frames on both panels alike, so the crossing costs a
      // press per frame rather than teleporting to the next cut.
      session.selectNextDrawing();
      expect(session.activeCutId, isNull, reason: 'parked in the gap');
      expect(session.editingGlobalFrame, duration);
      session.selectNextDrawing();
      expect(session.editingGlobalFrame, duration + 1);
      session.selectNextDrawing();
      expect(session.editingGlobalFrame, duration + 2);

      session.selectNextDrawing();
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
      session.selectNextDrawing();
      expect(
        session.activeCutId,
        cutBefore,
        reason:
            'a layer row lives inside one cut — that is why "which row '
            'of the next cut do I land on" never gets asked',
      );
    });
  });

  // A7① (2026-08-17): a HOLD is one flip unit — 「홀드 블록을 한 단위로
  // 건너뛰어 다음 프레임 선택」. The run-edge HOLD materializes a ghost
  // block right after the held block, and the flip used to treat that
  // ghost as its own column, landing exactly where the user reported
  // (「홀드 안쪽 2번 인덱스」) — while the flip HUD drew no block there.
  // The flip's column absorbs hold ghosts into their owning run now;
  // repeat ghosts stay their own columns (A7① names holds only).
  group('A7①: a HOLD is one flip unit', () {
    (EditorSessionManager, LayerId) heldSession(TimelineRunEdgeMode mode) {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      s.createDrawingAtCurrentFrame(); // 1-cell block at index 0
      final layerId = s.activeLayer!.id;
      s.setRunEdgeBehavior(
        layerId: layerId,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
        mode: mode,
      );
      return (s, layerId);
    }

    test('forward from the held block leaves past the ghost end — never '
        'lands inside the hold', () {
      final (s, _) = heldSession(TimelineRunEdgeMode.hold);
      addTearDown(s.dispose);
      final cutEnd = s.requireActiveCut.duration;

      s.selectFrameIndex(0);
      s.selectNextDrawing();
      expect(
        s.currentFrameIndex,
        cutEnd,
        reason: 'block + its hold ghost = ONE column ending at the cut end',
      );
    });

    test('backward from beyond lands on the AUTHORED head, and mid-ghost '
        'leaves the whole unit', () {
      final (s, _) = heldSession(TimelineRunEdgeMode.hold);
      addTearDown(s.dispose);
      final cutEnd = s.requireActiveCut.duration;

      s.selectFrameIndex(cutEnd);
      s.selectPreviousDrawing();
      expect(
        s.currentFrameIndex,
        0,
        reason: 'the previous column is the whole hold unit — its start is '
            'the authored head, not the ghost\'s',
      );

      s.selectFrameIndex(3); // inside the ghost
      s.selectNextDrawing();
      expect(s.currentFrameIndex, cutEnd, reason: 'mid-hold leaves whole');
    });

    test('REPEAT ghosts stay their own columns — A7① names holds only', () {
      final (s, _) = heldSession(TimelineRunEdgeMode.repeat);
      addTearDown(s.dispose);

      s.selectFrameIndex(0);
      s.selectNextDrawing();
      expect(
        s.currentFrameIndex,
        1,
        reason: 'each repeated part remains a flip column of its own',
      );
    });
  });
}
