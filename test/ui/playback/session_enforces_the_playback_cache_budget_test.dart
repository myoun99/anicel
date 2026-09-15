import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// THE SESSION'S ENFORCEMENT OF THE PLAYBACK CACHE BUDGET IS MEASURED.
///
/// `PlaybackCacheBudgetEnforcer` has its own tests (playback_cache_budget);
/// the session's `enforcePlaybackCacheBudget` — the one every producer
/// calls, handing the enforcer what to protect and what the screen has
/// pinned — had none. When the budget was carved out of the session as
/// `_PlaybackCacheBudget` (2026-09-02), the adversarial check made the
/// session's call a no-op and every test stayed green. The product budget
/// is 600 MB, which no unit test can fill, so the session grew a test seam
/// for the number; this fills a 256-byte budget with two 8×8 composites of
/// a cut that is NOT active (the active cut's range is protected) and asks
/// the session to enforce.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  // 8×8 RGBA = 256 bytes per full-quality composite.
  const fullImageBytes = 8 * 8 * 4;

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

  EditorSessionManager session() {
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
    s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(
      fullImageBytes,
    );
    return s;
  }

  /// A dab into [cut]'s cel, so its composite holds pixels (an empty cel
  /// composes to nothing, and nothing is cached).
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
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 1, y: 1),
          color: 0xFF000000,
          size: 2,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }

  testWidgets('the session trims the composites past its budget', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = session();
      expect(s.activeCutOrNull!.id, const CutId('cut-1'), reason: 'premise');
      expect(
        s.playbackRig.playbackCache.playbackCacheByteBudget,
        fullImageBytes,
        reason: 'the seam',
      );
      // Two cuts, two cels, two DIFFERENT composites — two frames of one
      // exposure share a signature and would share one image.
      for (final (id, frameId) in [
        ('cut-2', 'frame-b'),
        ('cut-3', 'frame-c'),
      ]) {
        final cut = s.cutById(CutId(id))!;
        draw(s, cut, '$id-layer', frameId);
        await s.renderCaches.cutFrameCompositeCache.prepareComposite(
          cut: cut,
          frameIndex: 0,
          quality: PlaybackQuality.full,
        );
      }
      expect(
        s.renderCaches.cutFrameCompositeCache.estimatedBytes,
        2 * fullImageBytes,
        reason: 'two composites of inactive cuts — twice the budget',
      );

      s.playbackRig.playbackCache.enforcePlaybackCacheBudget();

      expect(
        s.renderCaches.cutFrameCompositeCache.estimatedBytes,
        lessThanOrEqualTo(fullImageBytes),
        reason:
            'the session handed the enforcer its budget; cut-2 is not '
            'the active cut, so nothing protected it',
      );
    });
  });
}
