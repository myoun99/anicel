import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
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

/// A5 — ONE WARMING RESTART PER EDIT BURST, NOT ONE PER DAB.
///
/// Every brush invalidation used to call `_warmActiveCut()` directly, so a
/// stroke's stream of dab commits rebuilt the playhead-outward order,
/// bumped the scheduler's generation and reset its progress notifier once
/// per commit — pure churn, since warming cannot start until the idle
/// window has passed anyway. The debounce defers exactly ONE thing: the
/// restart. The cache invalidations stay synchronous, because a stale
/// composite must be unservable the instant the stroke lands.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  test('a burst of invalidations restarts warming once — and still drops '
      'the composite synchronously', () async {
    final cut = Cut(
      id: const CutId('cut'),
      name: '1',
      duration: 4,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: const LayerId('layer'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('frame-1'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('frame-1'), length: 4),
          },
        ),
      ],
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [cut]),
        ],
      ),
    );
    addTearDown(session.dispose);

    final activeCut = session.activeCutOrNull!;
    final frameKey = session.brushFrameKeyForCut(
      activeCut,
      const LayerId('layer'),
      const FrameId('frame-1'),
    );

    // Real content through the session's own store — a coordinator with
    // no hub wired, so nothing here counts as an edit burst yet.
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: session.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 2, y: 2),
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

    await session.cutFrameCompositeCache.prepareComposite(
      cut: activeCut,
      frameIndex: 0,
      quality: session.playbackQuality,
    );
    expect(
      session.cutFrameCompositeCache.validCompositeOrNull(
        cut: activeCut,
        frameIndex: 0,
        quality: session.playbackQuality,
      ),
      isNotNull,
    );

    // Let any open-time warm restart land before counting.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    var restarts = 0;
    void countRestarts() {
      final value = session.prerenderScheduler.progress.value;
      if (value.cached == 0 && value.total > 0) {
        restarts += 1;
      }
    }

    session.prerenderScheduler.progress.addListener(countRestarts);
    addTearDown(
      () => session.prerenderScheduler.progress.removeListener(countRestarts),
    );

    // The burst: five dab commits' worth of invalidations, synchronously.
    for (var i = 0; i < 5; i += 1) {
      session.cacheInvalidationHub.invalidateBrushFrame(
        BrushFrameCacheInvalidation(frameKey: frameKey, wholeFrame: true),
      );
    }

    expect(
      session.cutFrameCompositeCache.validCompositeOrNull(
        cut: activeCut,
        frameIndex: 0,
        quality: session.playbackQuality,
      ),
      isNull,
      reason: 'only the RESTART is deferred — a stale composite must be '
          'unservable before the event loop turns',
    );
    expect(
      restarts,
      0,
      reason: 'the restart waits for the burst\'s trailing edge',
    );

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      restarts,
      1,
      reason: 'five invalidations, one queue rebuild — that is the whole '
          'point of the debounce',
    );
  });
}
