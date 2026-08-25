import 'dart:typed_data';

import '../ui/dev_profile.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_stroke_commit_outcome.dart';
import '../models/canvas_size.dart';
import '../models/cut_id.dart';
import '../models/canvas_surface_state.dart';
import '../models/dirty_region.dart';
import '../models/brush_edit_session_state.dart';
import '../models/brush_frame_cache_invalidation.dart';
import '../models/brush_frame_key.dart';
import '../models/brush_history_policy.dart';
import '../models/dirty_tile_set.dart';
import 'brush_edit_session_cache_operations.dart';
import 'brush_frame_edit_session_store.dart';
import 'brush_frame_store.dart';
import 'cache_invalidation_executor.dart';

/// The brush editing spine (R19 P3b): sessions hold the CURRENT surface
/// only. Undo/redo live at the app level as pre/post SURFACE REFERENCES
/// (immutable tile maps — a snapshot is free), restored through
/// [restoreSurfaceSnapshot]. No command bookkeeping, no replay: the
/// raster is the truth end to end.
class BrushFrameEditingCoordinator {
  BrushFrameEditingCoordinator({
    required BrushFrameKey initialFrameKey,
    required this.frameStore,
    required this.sessionStore,
    required this.historyPolicy,
  }) : _activeFrameKey = initialFrameKey;

  final BrushFrameStore frameStore;
  final BrushFrameEditSessionStore sessionStore;
  final BrushHistoryPolicy historyPolicy;
  BrushFrameKey _activeFrameKey;

  BrushFrameKey get activeFrameKey => _activeFrameKey;
  BrushEditSessionState get activeSessionState => _sessionFor(_activeFrameKey);

  /// The cel's CURRENT pixels — the pre-image capture point for
  /// surface-snapshot undo entries.
  BitmapSurface currentSurfaceOf(BrushFrameKey key) =>
      _sessionFor(key).canvasState.currentSurface;

  void selectFrame(BrushFrameKey key) {
    frameStore.getOrCreateFrame(key);
    _sessionFor(key);
    _activeFrameKey = key;
    // Session-count budget (R13): sessions are thin now (current surface
    // only, shared with the baked truth), but unbounded growth is still
    // bookkeeping for nothing — evicted cels reseed from baked in O(1).
    sessionStore.evictBeyondRetainLimit(
      retainLimit: historyPolicy.retainedSessionLimit,
      protect: key,
    );
  }

  /// Adopts a new editing canvas size.
  ///
  /// Session surfaces and display caches are derived at the old size, so
  /// they are dropped and reseeded from the resized baked truth (R19: a
  /// resize is a raster crop/extend — pixels untouched).
  ///
  /// R27: the baked resize is STRICTLY scoped to [cutId]'s cels. Canvas
  /// sizes are per-cut, and this also runs on cut SWITCHES between
  /// different-sized cuts — the old store-global resize clipped every
  /// OTHER cut's cels to the newly active size (the 8K fill data-loss
  /// report). On a switch, the target cut's cels already sit at its
  /// size, so the scoped resize degenerates to pure adoption.
  void resizeCanvas(CanvasSize canvasSize, {required CutId cutId}) {
    if (canvasSize == sessionStore.canvasSize) {
      return;
    }
    sessionStore.resizeCanvas(canvasSize);
    frameStore.clearDisplayCaches();
    frameStore.resizeBakedSurfaces(canvasSize, cutId: cutId);
    _seedSession(_activeFrameKey);
  }

  /// Whole-store resize for SINGLE-CANVAS dedicated stores only (the
  /// timesheet ink planes). The main canvas coordinator must use the
  /// cut-scoped [resizeCanvas].
  void resizeCanvasAllCuts(CanvasSize canvasSize) {
    if (canvasSize == sessionStore.canvasSize) {
      return;
    }
    sessionStore.resizeCanvas(canvasSize);
    frameStore.clearDisplayCaches();
    frameStore.resizeAllBakedSurfacesSingleCanvas(canvasSize);
    _seedSession(_activeFrameKey);
  }

  /// Adopts [canvasSize] WITHOUT touching any baked cel — the cut-switch
  /// path when the new cut has no editable cels to scope a resize to.
  void adoptCanvasSize(CanvasSize canvasSize) {
    if (canvasSize == sessionStore.canvasSize) {
      return;
    }
    sessionStore.resizeCanvas(canvasSize);
    frameStore.clearDisplayCaches();
    _seedSession(_activeFrameKey);
  }

  BrushEditSessionState _sessionFor(BrushFrameKey key) {
    return sessionStore.sessionOrNull(key) ?? _seedSession(key);
  }

  /// Seeds the frame's session from the baked raster truth — O(1) and
  /// byte-exact (donations keep baked current across every mutation).
  /// A never-drawn cel seeds blank. The seed re-donates so the display
  /// cache is fresh whenever a session exists (e.g. right after a resize
  /// cleared every old-size cache).
  BrushEditSessionState _seedSession(BrushFrameKey key) {
    final blank = sessionStore.reset(key);
    final baked = frameStore.bakedSurfaceOrNull(key);
    if (baked == null || baked.canvasSize != sessionStore.canvasSize) {
      return blank;
    }
    final seeded = sessionStore.update(
      key,
      blank.copyWith(canvasState: CanvasSurfaceState(currentSurface: baked)),
    );
    _donateSessionSurfaceToDisplayCache(key, seeded);
    return seeded;
  }

  /// Donates the session's post-edit surface to the store's display cache.
  ///
  /// The commit fast path already produced the exact post-stroke pixels
  /// (byte-identical across the three blend routes — the parity suites pin
  /// live == commit == reference), and [BitmapSurface] is an immutable tile
  /// map, so sharing it is a free snapshot. Downstream consumers (playback
  /// layer images, storyboard thumbnails, camera preview) read it instead
  /// of ever re-deriving pixels.
  void _donateSessionSurfaceToDisplayCache(
    BrushFrameKey key,
    BrushEditSessionState sessionState,
  ) {
    final surface = sessionState.canvasState.currentSurface;
    frameStore.storeRebuiltDisplayCache(key: key, previewSurface: surface);
    // R19 bake-only: the donation IS the bake — every commit and every
    // snapshot restore lands the exact pixels as the cel's raster truth
    // (immutable surface, shared instance, no copy).
    frameStore.storeBakedSurface(key, surface);
  }

  /// Commits a finished stroke into the active cel's surface and returns
  /// its surface transition — the caller's undo payload (R19 P3b).
  ///
  /// Returns `null` when the stroke changed no pixels: a no-op stroke
  /// must create no undo entry.
  BrushStrokeCommitOutcome? commitSourceStroke({
    required List<BrushDab> sourceDabs,
    CacheInvalidationSink? cacheInvalidationSink,
    Uint8List? prerasterizedStrokePixels,
    DirtyRegion? prerasterizedStrokeBounds,
    BrushBlendMode blendMode = BrushBlendMode.color,
    double strokeOpacity = 1,
    BitmapSurface? promotedBase,
    List<BitmapTile>? promotedTiles,
  }) {
    if (sourceDabs.isEmpty) {
      throw ArgumentError.value(sourceDabs, 'sourceDabs', 'must not be empty');
    }

    final before = activeSessionState;
    final preSurface = before.canvasState.currentSurface;
    final result = labProbe(
      'commit.materialize',
      () => commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation(
        sessionState: before,
        sequence: BrushDabSequence(sourceDabs, strokeOpacity),
        layerId: _activeFrameKey.layerId,
        frameId: _activeFrameKey.frameId,
        cacheInvalidationSink:
            cacheInvalidationSink ?? _NoopCacheInvalidationSink(),
        prerasterizedStrokePixels: prerasterizedStrokePixels,
        prerasterizedStrokeBounds: prerasterizedStrokeBounds,
        blendMode: blendMode,
        promotedBase: promotedBase,
        promotedTiles: promotedTiles,
      ),
    );
    final committedState = result.sessionState;
    sessionStore.update(_activeFrameKey, committedState);
    final affectedEntry = result.affectedEntry;
    if (affectedEntry == null) {
      return null;
    }

    labProbe(
      'commit.markEdited',
      () => frameStore.markCelEdited(
        _activeFrameKey,
        dirtyTiles: affectedEntry.dirtyTiles,
      ),
    );
    labProbe(
      'commit.donate',
      () =>
          _donateSessionSurfaceToDisplayCache(_activeFrameKey, committedState),
    );
    labProbe(
      'commit.invalidate',
      () => _invalidateBrushFrame(
        cacheInvalidationSink,
        _activeFrameKey,
        dirtyTiles: affectedEntry.dirtyTiles,
      ),
    );
    return BrushStrokeCommitOutcome(
      preSurface: preSurface,
      postSurface: committedState.canvasState.currentSurface,
      dirtyTiles: affectedEntry.dirtyTiles,
    );
  }

  /// THE undo/redo primitive (R19 P3b): makes [surface] the cel's current
  /// pixels — session, baked truth, display cache and downstream caches
  /// all follow. Undo restores an entry's pre-surface, redo its
  /// post-surface; both are plain references, so this is O(changed tiles)
  /// in GC terms and O(1) in copies.
  ///
  /// A surface captured at a different canvas size is refused (debug
  /// assert, release no-op): the LIFO history order means a
  /// ResizeCutCanvasCommand always unwinds first, so this only trips on a
  /// programming error.
  void restoreSurfaceSnapshot(
    BrushFrameKey key,
    BitmapSurface surface, {
    CacheInvalidationSink? cacheInvalidationSink,
  }) {
    assert(
      surface.canvasSize == sessionStore.canvasSize,
      'surface snapshot size ${surface.canvasSize} != session canvas '
      '${sessionStore.canvasSize} — undo order must unwind resizes first',
    );
    if (surface.canvasSize != sessionStore.canvasSize) {
      return;
    }
    final blank = sessionStore.reset(key);
    final state = sessionStore.update(
      key,
      blank.copyWith(canvasState: CanvasSurfaceState(currentSurface: surface)),
    );
    frameStore.markCelEdited(key);
    _donateSessionSurfaceToDisplayCache(key, state);
    _invalidateBrushFrame(cacheInvalidationSink, key);
  }

  void _invalidateBrushFrame(
    CacheInvalidationSink? sink,
    BrushFrameKey key, {
    DirtyTileSet? dirtyTiles,
  }) {
    (sink ?? _NoopCacheInvalidationSink()).invalidateBrushFrame(
      BrushFrameCacheInvalidation(
        frameKey: key,
        dirtyTiles: dirtyTiles,
        wholeFrame: dirtyTiles == null || dirtyTiles.isEmpty,
      ),
    );
  }
}

class _NoopCacheInvalidationSink implements CacheInvalidationSink {
  @override
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation) {}

  @override
  void invalidateFrameComposite(key) {}
  @override
  void invalidateLayerTile(key) {}
  @override
  void invalidatePlaybackPreview(key) {}
}
