import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/editor_cache_invalidation_hub.dart';

void main() {
  BrushFrameCacheInvalidation invalidation() => BrushFrameCacheInvalidation(
    frameKey: const BrushFrameKey(
      projectId: ProjectId('project'),
      trackId: TrackId('track'),
      cutId: CutId('cut'),
      layerId: LayerId('layer'),
      frameId: FrameId('frame'),
    ),
    wholeFrame: true,
  );

  test('dispatches brush frame invalidations to every listener', () {
    final hub = EditorCacheInvalidationHub();
    final first = <BrushFrameCacheInvalidation>[];
    final second = <BrushFrameCacheInvalidation>[];
    hub.addBrushFrameListener(first.add);
    hub.addBrushFrameListener(second.add);

    hub.invalidateBrushFrame(invalidation());

    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(first.single.frameKey.frameId, const FrameId('frame'));
  });

  test('removed listeners stop receiving events', () {
    final hub = EditorCacheInvalidationHub();
    final received = <BrushFrameCacheInvalidation>[];
    hub.addBrushFrameListener(received.add);
    hub.removeBrushFrameListener(received.add);

    hub.invalidateBrushFrame(invalidation());

    expect(received, isEmpty);
  });

  test('stroke commit, undo and redo reach the hub end-to-end', () {
    final hub = EditorCacheInvalidationHub();
    final received = <BrushFrameCacheInvalidation>[];
    hub.addBrushFrameListener(received.add);

    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: invalidation().frameKey,
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: const CanvasSize(width: 8, height: 8),
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    );

    final outcome = coordinator.commitSourceStroke(
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
      cacheInvalidationSink: hub,
    )!;
    expect(received, hasLength(1));
    expect(received.single.hasDirtyTiles, isTrue);

    // Undo/redo = surface snapshot restores (R19 P3b) — both invalidate.
    coordinator.restoreSurfaceSnapshot(
      coordinator.activeFrameKey,
      outcome.preSurface,
      cacheInvalidationSink: hub,
    );
    coordinator.restoreSurfaceSnapshot(
      coordinator.activeFrameKey,
      outcome.postSurface,
      cacheInvalidationSink: hub,
    );
    expect(received, hasLength(3));
  });

  test('a listener removing itself during dispatch is safe', () {
    final hub = EditorCacheInvalidationHub();
    var calls = 0;
    late void Function(BrushFrameCacheInvalidation) listener;
    listener = (_) {
      calls += 1;
      hub.removeBrushFrameListener(listener);
    };
    hub.addBrushFrameListener(listener);

    hub.invalidateBrushFrame(invalidation());
    hub.invalidateBrushFrame(invalidation());

    expect(calls, 1);
  });
}
