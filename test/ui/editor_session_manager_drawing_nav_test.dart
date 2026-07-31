import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
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

  test('next: jumps to the block start, ESCAPES past the block end, then '
      'steps frames through empty space (PEN-12 #2)', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(0);
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 2, reason: 'jumps to the block');

    // ON the last block with no next drawing: one press escapes past its
    // end — never a one-frame crawl through a long tail block.
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 5, reason: 'escapes the block whole');

    // Pure empty space keeps the PEN-8 one-frame walk.
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 6);

    // From INSIDE the block the escape lands past the end too.
    session.selectFrameIndex(3);
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 5, reason: 'mid-block escapes whole');
  });

  test('previous: steps frames through empty space, then jumps to the '
      'block start', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(7);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 2, reason: 'jumps back to the block');

    // Before the block there is no earlier drawing — empty space walks
    // one frame at a time (and clamps at 0).
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 1);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 0);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 0, reason: 'clamped at the start');
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

      // Mid-cut, backwards lands on THIS cut's start — the same
      // clip-navigation convention a layer block follows.
      session.selectFrameIndex(5);
      session.selectPreviousDrawing();
      expect(session.activeCutId, const CutId('cut-3'));
      expect(session.currentFrameIndex, 0);

      session.selectPreviousDrawing();
      expect(session.activeCutId, const CutId('cut-2'));
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
        reason: 'a layer row lives inside one cut — that is why "which row '
            'of the next cut do I land on" never gets asked',
      );
    });
  });
}
