import 'dart:ui' as ui;

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/playback_quality.dart';
import '../../services/brush_frame_display_cache_service.dart';
import '../../services/brush_frame_store.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../dev_profile.dart';
import '../canvas/deferred_image_disposal.dart';
import '../canvas/tiled_surface_compose.dart';
import 'playback_cache_budget.dart';

/// One cached layer-frame render: the image plus the CANVAS-SPACE rect it
/// covers ([worldRect] == the canvas rect unless the cel has pasteboard
/// tiles, which grow the extent so the editing stack can show them).
class LayerFrameImage {
  const LayerFrameImage({required this.image, required this.worldRect});

  final ui.Image image;
  final ui.Rect worldRect;
}

class _LayerFrameImageEntry {
  _LayerFrameImageEntry({
    required this.positioned,
    required this.sourceRevision,
    required this.canvasSize,
    required this.lastUsed,
  });

  /// The stable per-entry wrapper — cache hits return the SAME instance,
  /// so `identical` remains a valid hit oracle for consumers and tests.
  final LayerFrameImage positioned;
  final int sourceRevision;
  final CanvasSize canvasSize;
  int lastUsed;

  ui.Image get image => positioned.image;
}

/// Level-1 playback cache: one GPU [ui.Image] per (layer frame, quality),
/// built from the brush store's display-cache surface (the first production
/// consumer of [BrushFrameDisplayCacheService]).
///
/// Validity is revision-based: an entry is valid iff its stored
/// `sourceRevision` (and canvas size) still match the store's current
/// drawing state, so brush edits and undo/redo invalidate without any event
/// plumbing. [invalidateFrame] additionally drops entries eagerly on sink
/// events to free memory sooner.
class LayerFrameImageCache {
  LayerFrameImageCache({required this.frameStore});

  final BrushFrameStore frameStore;
  final Map<(BrushFrameKey, PlaybackQuality), _LayerFrameImageEntry> _entries =
      {};
  int _useCounter = 0;

  /// The cached image when it still matches the frame's current source
  /// revision and [canvasSize]; `null` on miss or staleness.
  LayerFrameImage? validImageOrNull(
    BrushFrameKey key,
    PlaybackQuality quality, {
    required CanvasSize canvasSize,
  }) {
    final entry = _entries[(key, quality)];
    if (entry == null ||
        entry.canvasSize != canvasSize ||
        entry.sourceRevision != _currentRevision(key)) {
      return null;
    }
    entry.lastUsed = ++_useCounter;
    return entry.positioned;
  }

  /// Returns a valid image, rebuilding it when missing or stale. `null` when
  /// the frame has no drawn content — or, with [shouldAbort] (the warm path,
  /// R13-4), when the build was abandoned mid-way: aborts cache nothing and
  /// the abort checks bracket the two big slices (the display-cache replay
  /// and each tile decode via [composePositionedSurfaceImage]).
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    bool Function()? shouldAbort,
  }) async {
    final cached = validImageOrNull(key, quality, canvasSize: canvasSize);
    if (cached != null) {
      return cached;
    }

    // Content oracle, not a command check (R19 P3a): an OPENED cel's
    // picture is its baked raster and carries no commands at all — the
    // old command-emptiness guard blanked every loaded cel in playback.
    final drawing = frameStore.frameOrNull(key);
    if (drawing == null || !frameStore.celHasRenderableContent(key)) {
      _dropEntry((key, quality));
      return null;
    }
    final revision = drawing.sourceRevision;

    // The display-cache replay is the one monolithic CPU slice on this
    // path (it grows with the cel's stroke count) — never START it when
    // the editor just went hot.
    if (shouldAbort?.call() ?? false) {
      return null;
    }
    final previewCache = BrushFrameDisplayCacheService(
      frameStore: frameStore,
      canvasSize: canvasSize,
    ).prepareFramePreview(key);
    if (!previewCache.isValid) {
      // A cel that HAS pixels, recorded at another canvas size. Composing
      // the blank stand-in and banking it here under [revision] is what
      // makes the row stay blank: the revision does not move when a heal
      // repairs the size, so the empty image is served for ever after.
      // No image this pass, nothing remembered, next pass gets to look.
      return null;
    }
    final preview = previewCache.previewSurface;

    // Per-tile GPU compose over the CONTENT extent (canvas rect grown by
    // any pasteboard tiles): the editing canvas keeps the on-screen
    // frame's tiles decoded in the shared cache, so the post-stroke
    // rebuild draws existing tile images instead of assembling + uploading
    // the whole canvas — cost follows the CHANGED tiles, not the canvas.
    var positioned = await composePositionedSurfaceImage(
      preview,
      reuse: BitmapTileImageCache.instance,
      shouldAbort: shouldAbort,
    );
    if (positioned == null) {
      return null;
    }
    if (quality != PlaybackQuality.full) {
      final scale =
          scaledCanvasSize(canvasSize, quality).width / canvasSize.width;
      final downscaled = await _downscale(
        positioned.image,
        width: (positioned.worldRect.width * scale).round().clamp(1, 1 << 24),
        height: (positioned.worldRect.height * scale).round().clamp(1, 1 << 24),
      );
      positioned.image.dispose();
      // The worldRect stays CANVAS-SPACE — consumers map src→worldRect,
      // so the raster resolution is free to differ.
      positioned = PositionedSurfaceImage(
        image: downscaled,
        worldRect: positioned.worldRect,
      );
    }

    _dropEntry((key, quality));
    final result = LayerFrameImage(
      image: positioned.image,
      worldRect: positioned.worldRect,
    );
    _entries[(key, quality)] = _LayerFrameImageEntry(
      positioned: result,
      sourceRevision: revision,
      canvasSize: canvasSize,
      lastUsed: ++_useCounter,
    );
    return result;
  }

  /// Synchronous fast path for the editing canvas's layer-switch handoff:
  /// the valid cached image, or — full quality only — a sync compose from
  /// tiles already decoded in the shared tile cache (the just-deactivated
  /// on-screen frame's tiles always are). `null` means the caller must
  /// fall back to [prepare].
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
  }) {
    final cached = validImageOrNull(key, quality, canvasSize: canvasSize);
    if (cached != null) {
      return cached;
    }
    if (quality != PlaybackQuality.full) {
      return null;
    }

    final drawing = frameStore.frameOrNull(key);
    if (drawing == null || !frameStore.celHasRenderableContent(key)) {
      return null;
    }
    final revision = drawing.sourceRevision;

    final previewCache = labProbe(
      'prepareFramePreview(${key.frameId.value} rev${drawing.sourceRevision})',
      () => BrushFrameDisplayCacheService(
        frameStore: frameStore,
        canvasSize: canvasSize,
      ).prepareFramePreview(key),
    );
    if (!previewCache.isValid) {
      // The size miss again — see the async twin. Banking the blank under
      // a revision that a heal never moves is what freezes the row.
      return null;
    }
    final preview = previewCache.previewSurface;
    final positioned = composePositionedSurfaceImageSyncOrNull(
      preview,
      reuse: BitmapTileImageCache.instance,
    );
    if (positioned == null) {
      return null;
    }

    _dropEntry((key, quality));
    final result = LayerFrameImage(
      image: positioned.image,
      worldRect: positioned.worldRect,
    );
    _entries[(key, quality)] = _LayerFrameImageEntry(
      positioned: result,
      sourceRevision: revision,
      canvasSize: canvasSize,
      lastUsed: ++_useCounter,
    );
    return result;
  }

  /// Eagerly drops every quality of one layer frame (sink-event eviction).
  void invalidateFrame(BrushFrameKey key) {
    for (final quality in PlaybackQuality.values) {
      _dropEntry((key, quality));
    }
  }

  int get estimatedBytes {
    var total = 0;
    for (final entry in _entries.values) {
      total += estimatedImageBytes(entry.image.width, entry.image.height);
    }
    return total;
  }

  /// Evicts least-recently-used entries until at or under [targetBytes].
  void evictLeastRecentlyUsed({required int targetBytes}) {
    final ordered = _entries.entries.toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    var bytes = estimatedBytes;
    for (final entry in ordered) {
      if (bytes <= targetBytes) {
        break;
      }
      // ⛔A pinned slot is ON SCREEN. Evicting it returns zero bytes
      // anyway (the holder's clone shares the pixels) and puts the very
      // image the canvas is drawing back on the cold path — the "worked
      // harder, got emptier" loop PR #1065 documented. Recency cannot
      // express "someone is holding this"; only the pin can.
      if (_pins.containsKey(entry.key)) {
        continue;
      }
      bytes -= estimatedImageBytes(
        entry.value.image.width,
        entry.value.image.height,
      );
      _dropEntry(entry.key);
    }
  }

  // --- Display pins (A6) ----------------------------------------------
  //
  // The editing canvas holds CLONES of cache images, and a clone shares
  // pixels: dropping the entry "freed" bytes that stayed fully alive, so
  // every budget figure downstream was fiction — the reserve PR #1065
  // added was sized by an estimate that saturated at twenty layers. The
  // pin is the holder saying "these pixels are on screen": eviction skips
  // the slot, and [pinnedBytes] is the MEASURED reserve that replaces the
  // estimate.

  final Map<(BrushFrameKey, PlaybackQuality), int> _pins = {};

  /// Declares a holder of [key]'s image at [quality]. Balanced by
  /// [releasePin]; counts nest, because two widgets may hold the same
  /// slot's clone.
  void retainPin(BrushFrameKey key, PlaybackQuality quality) {
    final slot = (key, quality);
    _pins[slot] = (_pins[slot] ?? 0) + 1;
  }

  void releasePin(BrushFrameKey key, PlaybackQuality quality) {
    final slot = (key, quality);
    final count = _pins[slot];
    if (count == null) {
      assert(false, 'releasePin without a matching retainPin: $slot');
      return;
    }
    if (count <= 1) {
      _pins.remove(slot);
    } else {
      _pins[slot] = count - 1;
    }
  }

  /// The bytes of every pinned slot's CURRENT entry — what the screen is
  /// actually holding, measured, not estimated. Walks the pins, not the
  /// entries: the pin set is the visible layer count.
  int get pinnedBytes {
    var total = 0;
    for (final slot in _pins.keys) {
      final entry = _entries[slot];
      if (entry != null) {
        total += estimatedImageBytes(entry.image.width, entry.image.height);
      }
    }
    return total;
  }

  void dispose() {
    for (final key in _entries.keys.toList()) {
      _dropEntry(key);
    }
  }

  int _currentRevision(BrushFrameKey key) =>
      frameStore.frameOrNull(key)?.sourceRevision ?? 0;

  void _dropEntry((BrushFrameKey, PlaybackQuality) cacheKey) {
    final entry = _entries.remove(cacheKey);
    if (entry != null) {
      // Deferred, never direct: the image may still be referenced by the
      // frame currently on screen (same race the tile cache guards against).
      DeferredImageDisposer.instance.retire(entry.image);
    }
  }

  Future<ui.Image> _downscale(
    ui.Image source, {
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }
}
