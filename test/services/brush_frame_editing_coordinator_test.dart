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
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cache_invalidation_executor.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';

/// R19 P3b coordinator contract: sessions hold the CURRENT surface only,
/// commits return their surface transition, and [restoreSurfaceSnapshot]
/// is THE undo/redo primitive — byte-exact, donation-backed, replay-free.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  BrushFrameKey key(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  BrushFrameEditingCoordinator coordinator({int retainedSessionLimit = 4}) {
    return BrushFrameEditingCoordinator(
      initialFrameKey: key('frame-a'),
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
        retainedSessionLimit: retainedSessionLimit,
      ),
    );
  }

  int alphaAt(BrushFrameEditingCoordinator c, int x, int y) {
    // Whole-pixel oracle: 0 = fully transparent, anything else = ink.
    return surfacePixelRgba(c.currentSurfaceOf(c.activeFrameKey), x, y) ?? 0;
  }

  test('commit returns the surface transition: pre is the pre-stroke '
      'surface BY IDENTITY, post is the live surface, pixels landed', () {
    final c = coordinator();
    final before = c.currentSurfaceOf(c.activeFrameKey);

    final outcome = c.commitSourceStroke(sourceDabs: [_dab(0)])!;

    expect(identical(outcome.preSurface, before), isTrue);
    expect(
      identical(outcome.postSurface, c.currentSurfaceOf(c.activeFrameKey)),
      isTrue,
    );
    expect(outcome.dirtyTiles.isNotEmpty, isTrue);
    expect(outcome.estimatedRetainedBytes, greaterThan(0));
    expect(alphaAt(c, 2, 2), greaterThan(0));
  });

  test('a no-pixel stroke returns null and retains nothing', () {
    final c = coordinator();
    final outcome = c.commitSourceStroke(
      sourceDabs: [_dab(0).copyWith(opacity: 0)],
    );
    expect(outcome, isNull);
  });

  test('commit donates: valid display cache at the new revision, baked '
      'truth updated, sink sees the dirty tiles', () {
    final c = coordinator();
    final sink = _RecordingSink();

    c.commitSourceStroke(sourceDabs: [_dab(0)], cacheInvalidationSink: sink);

    expect(sink.brushFrames, hasLength(1));
    expect(sink.brushFrames.single.frameKey, c.activeFrameKey);
    expect(sink.brushFrames.single.hasDirtyTiles, isTrue);
    expect(sink.brushFrames.single.wholeFrame, isFalse);
    final frame = c.frameStore.getOrCreateFrame(c.activeFrameKey);
    expect(frame.inactivePreviewDirty, isFalse);
    expect(frame.cacheDirtyTiles.isEmpty, isTrue);
    final cache = c.frameStore.displayCacheOrNull(c.activeFrameKey)!;
    expect(cache.isValid, isTrue);
    expect(cache.sourceRevision, frame.sourceRevision);
    expect(
      identical(
        cache.previewSurface,
        c.frameStore.bakedSurfaceOrNull(c.activeFrameKey),
      ),
      isTrue,
      reason: 'the donation IS the bake — one shared immutable surface',
    );
  });

  test('restoreSurfaceSnapshot round-trips undo/redo byte-exactly and '
      'donates each restore', () {
    final c = coordinator();
    final outcome = c.commitSourceStroke(sourceDabs: [_dab(0)])!;
    expect(alphaAt(c, 2, 2), greaterThan(0));

    c.restoreSurfaceSnapshot(c.activeFrameKey, outcome.preSurface);
    expect(alphaAt(c, 2, 2), 0, reason: 'undo = the pre surface, exactly');
    expect(
      c.frameStore.bakedSurfaceOrNull(c.activeFrameKey),
      isNull,
      reason: 'a blank restore removes the baked truth (empty tiles)',
    );

    c.restoreSurfaceSnapshot(c.activeFrameKey, outcome.postSurface);
    expect(
      identical(c.currentSurfaceOf(c.activeFrameKey), outcome.postSurface),
      isTrue,
      reason: 'redo = the post surface REFERENCE, no copies anywhere',
    );
    expect(
      identical(
        c.frameStore.bakedSurfaceOrNull(c.activeFrameKey),
        outcome.postSurface,
      ),
      isTrue,
    );
  });

  test('undo entries are EVICTION-PROOF: a snapshot restores after the '
      'session was dropped and reseeded from baked', () {
    final c = coordinator(retainedSessionLimit: 2);
    final frameA = c.activeFrameKey;
    final outcome = c.commitSourceStroke(sourceDabs: [_dab(0)])!;

    // Draw across enough cels to evict frame-a's session.
    for (final id in ['frame-b', 'frame-c', 'frame-d']) {
      c.selectFrame(key(id));
      c.commitSourceStroke(sourceDabs: [_dab(1)]);
    }
    expect(c.sessionStore.sessionOrNull(frameA), isNull);

    // Revisit: the session reseeds from baked BY IDENTITY (O(1), exact).
    c.selectFrame(frameA);
    expect(
      identical(
        c.currentSurfaceOf(frameA),
        c.frameStore.bakedSurfaceOrNull(frameA),
      ),
      isTrue,
    );

    // The app-level entry still restores exactly — no replay involved.
    c.restoreSurfaceSnapshot(frameA, outcome.preSurface);
    expect(alphaAt(c, 2, 2), 0);
    c.restoreSurfaceSnapshot(frameA, outcome.postSurface);
    expect(alphaAt(c, 2, 2), greaterThan(0));
  });

  test('a snapshot at the wrong canvas size is refused (no-op)', () {
    final c = coordinator();
    final outcome = c.commitSourceStroke(sourceDabs: [_dab(0)])!;
    c.resizeCanvas(const CanvasSize(width: 4, height: 4), cutId: const CutId('cut'));

    expect(
      () => c.restoreSurfaceSnapshot(c.activeFrameKey, outcome.postSurface),
      throwsA(isA<AssertionError>()),
      reason: 'debug builds assert — LIFO must unwind resizes first',
    );
  });

  test('selectFrame keeps at most retainedSessionLimit sessions', () {
    final c = coordinator(retainedSessionLimit: 2);
    c.commitSourceStroke(sourceDabs: [_dab(0)]);
    for (final id in ['frame-b', 'frame-c', 'frame-d']) {
      c.selectFrame(key(id));
      c.commitSourceStroke(sourceDabs: [_dab(1)]);
    }
    expect(c.sessionStore.sessionCount, 2);
    expect(c.sessionStore.sessionOrNull(key('frame-d')), isNotNull);
  });

  test('resizeCanvas reseeds the active session from the resized baked '
      'truth (pixels preserved, PS crop semantics)', () {
    final c = coordinator();
    c.commitSourceStroke(sourceDabs: [_dab(0)]);
    expect(alphaAt(c, 2, 2), greaterThan(0));

    c.resizeCanvas(const CanvasSize(width: 12, height: 12), cutId: const CutId('cut'));

    expect(
      c.currentSurfaceOf(c.activeFrameKey).canvasSize,
      const CanvasSize(width: 12, height: 12),
    );
    expect(alphaAt(c, 2, 2), greaterThan(0), reason: 'content survives grow');
  });
}

BrushDab _dab(int sequence) => BrushDab(
  center: CanvasPoint(x: 2, y: 2),
  color: 0xFF112233,
  size: 3,
  opacity: 1,
  flow: 1,
  hardness: 1,
  tipShape: BrushTipShape.round,
  pressure: 1,
  sequence: sequence,
);

class _RecordingSink implements CacheInvalidationSink {
  final List<BrushFrameCacheInvalidation> brushFrames = [];

  @override
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation) {
    brushFrames.add(invalidation);
  }

  @override
  void invalidateFrameComposite(key) {}
  @override
  void invalidateLayerTile(key) {}
  @override
  void invalidatePlaybackPreview(key) {}
}
