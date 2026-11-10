import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart' show defaultCelTileSize;
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// THE SESSION'S ENFORCEMENT OF THE PLAYBACK CACHE BUDGET IS MEASURED.
///
/// `PlaybackCacheBudgetEnforcer` has its own tests (playback_cache_budget);
/// the session's `enforcePlaybackCacheBudget` — the one every producer
/// calls, handing the enforcer what is wanted and what the screen has
/// pinned — had none. When the budget was carved out of the session as
/// `_PlaybackCacheBudget` (2026-09-02), the adversarial check made the
/// session's call a no-op and every test stayed green. The product budget
/// is 600 MB, which no unit test can fill, so the session grew a test seam
/// for the number; this fills a budget of one picture with two frames' 8×8
/// pictures and asks the session to enforce.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Cut cut(String id, String frameId) => Cut(
    id: CutId(id),
    name: id,
    duration: 2,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: LayerId('$id-layer'),
        name: 'A',
        frames: [Frame(id: FrameId(frameId), duration: 2, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(FrameId(frameId), length: 2)},
      ),
    ],
  );

  EditorSessionManager session({required int budget}) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('budget'),
        name: 'Budget',
        createdAt: DateTime.utc(2026, 9, 2),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              cut('cut-1', 'frame-a'),
              cut('cut-2', 'frame-b'),
              cut('cut-3', 'frame-c'),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    // Before the first cache use — the enforcer reads it once, when built.
    s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(budget);
    return s;
  }

  /// A dab across all four of [cut]'s tiles and inside its canvas, so its
  /// picture is the canvas's size (an empty cel asks for no picture at all).
  /// ⚠️A dab past the edge puts the cel on the pasteboard's tiles, and its
  /// picture is then theirs.
  void draw(EditorSessionManager s, Cut cut, String layerId, String frameId) {
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        cut,
        LayerId(layerId),
        FrameId(frameId),
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: defaultCelTileSize,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 4, y: 4),
          color: 0xFF000000,
          size: 6,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.square,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }


  /// [cut]'s first frame, made as the warmer makes it.
  Future<void> make(EditorSessionManager s, Cut cut) =>
      s.playbackRig.framePictures.make((
        cut: cut,
        frameIndex: 0,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      ), shouldAbort: () => false);

  /// What [cut]'s first frame's picture is kept under.
  FramePictureKey keyOf(EditorSessionManager s, Cut cut) => s
      .playbackRig
      .framePictures
      .keyOf((cut: cut, frameIndex: 0, paintPaper: true, ghosts: FrameGhosts.none));

  /// What one frame's picture weighs: a cel inked over its canvas, laid as
  /// the store lays it — measured, on a line it fits in many times.
  Future<int> onePicture() async {
    final s = session(budget: 1 << 30);
    final cut = s.cutById(const CutId('cut-2'))!;
    draw(s, cut, 'cut-2-layer', 'frame-b');
    await make(s, cut);
    return s.renderCaches.framePictureStore.bytesOf(keyOf(s, cut))!;
  }

  /// Draws cut-2's and cut-3's cels and makes their frames: two cuts, two
  /// cels, two pictures — two frames of one exposure would share one.
  Future<void> twoPictures(EditorSessionManager s) async {
    for (final (id, frameId) in [('cut-2', 'frame-b'), ('cut-3', 'frame-c')]) {
      final cut = s.cutById(CutId(id))!;
      draw(s, cut, '$id-layer', frameId);
      await make(s, cut);
    }
  }

  testWidgets('the session trims the pictures past its budget', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final one = await onePicture();
      final s = session(budget: one);
      expect(s.activeCutOrNull!.id, const CutId('cut-1'), reason: 'premise');
      expect(
        s.playbackRig.playbackCache.playbackCacheByteBudget,
        one,
        reason: 'the seam',
      );
      await twoPictures(s);
      final pictures = s.renderCaches.framePictureStore;
      expect(
        pictures.estimatedBytes,
        2 * one,
        reason: 'two pictures of inactive cuts — twice the budget',
      );

      s.playbackRig.playbackCache.enforcePlaybackCacheBudget();

      expect(
        pictures.estimatedBytes,
        lessThanOrEqualTo(one),
        reason: 'the session handed the enforcer its budget',
      );
    });
  });
}
