import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../models/bitmap_tile.dart';
import '../../models/tile_coord.dart';
import '../../native/qa_native_engine.dart';
import 'deferred_image_disposal.dart';

/// Identity-keyed cache converting immutable [BitmapTile] pixel bytes into
/// GPU-ready [ui.Image]s for display.
///
/// This is derived render data only — never source of truth. Tiles are
/// immutable and structurally shared across [BitmapSurface] versions, so the
/// tile object's identity is a stable cache key: an unchanged tile keeps its
/// decoded image across surface updates, and a changed tile is a new object
/// that decodes once.
///
/// Decoding is asynchronous; [BitmapSurfacePainter] falls back to its
/// per-pixel path for tiles whose image is not ready yet and repaints via the
/// [ChangeNotifier] interface when a decode completes. Entries never need
/// manual eviction: the [Expando] releases them with the tile, and a
/// [Finalizer] disposes the decoded image afterwards.
class BitmapTileImageCache extends ChangeNotifier {
  BitmapTileImageCache();

  /// Shared instance used by the display painter. A render cache, not app
  /// state: it holds no editing data and only accelerates repaints.
  static final BitmapTileImageCache instance = BitmapTileImageCache();

  final Expando<ui.Image> _images = Expando<ui.Image>('bitmapTileImages');
  final Expando<Object> _inFlight = Expando<Object>('bitmapTileImageDecodes');
  static const Object _inFlightMarker = Object();
  // Deferred, not direct, disposal: the finalizer runs at GC time — pen-up
  // commits allocate heavily and collect right when a replaced tile's image
  // is still referenced by the frame on screen. Disposing it there raced
  // the raster thread and intermittently flashed the tile as a black square
  // for one frame.
  static final Finalizer<ui.Image> _imageFinalizer = Finalizer<ui.Image>(
    (image) => DeferredImageDisposer.instance.retire(image),
  );

  /// Latest decoded tile per (scope, coordinate), held strongly so its image
  /// stays alive (the [Finalizer] only disposes an image once its tile is
  /// unreferenced everywhere). Lets the painter show slightly stale content
  /// for a just-changed tile instead of falling back to a per-pixel redraw,
  /// which froze the UI for large strokes.
  ///
  /// The scope isolates unrelated surfaces that share coordinates — e.g. two
  /// animation frames both have a tile at (0, 0), and without scoping the
  /// previous frame's artwork would briefly show through while the current
  /// frame's tile decodes.
  ///
  /// SCOPE-BUDGETED (R13): scopes are per-cel, and without a cap every cel
  /// ever edited pinned its last-decoded tile generation (pixel bytes AND
  /// gpu images, tens of MB per painted cel) for the rest of the run —
  /// another "the more I draw, the slower everything gets" term. Insertion
  /// order doubles as recency; scopes beyond [retainedScopeLimit] drop from
  /// the least-recent end (their stale-fallback simply degrades to a
  /// one-frame decode wait on revisit).
  final Map<Object?, Map<TileCoord, BitmapTile>> _latestDecodedByScope =
      <Object?, Map<TileCoord, BitmapTile>>{};

  /// Maximum scopes (≈ recently edited cels) whose stale-fallback tiles
  /// stay pinned.
  static const int retainedScopeLimit = 8;

  /// The decoded image for [tile], or `null` while the decode is pending.
  ui.Image? imageFor(BitmapTile tile) => _images[tile];

  /// The most recently decoded image at [coord] within [scope] (possibly for
  /// an older tile version), or `null` if nothing decoded there yet.
  ui.Image? latestImageForCoord(TileCoord coord, {Object? scope}) {
    final tile = _latestDecodedByScope[scope]?[coord];
    return tile == null ? null : _images[tile];
  }

  /// Whether [ensureDecoded] would actually start work for [tile] — no
  /// decoded image yet and no decode in flight. The painter's decode
  /// chunking (R18 B-1) uses this to collect pending tiles without paying
  /// the start cost.
  bool needsDecodeStart(BitmapTile tile) =>
      _images[tile] == null && _inFlight[tile] == null;

  /// Decode STARTS a consumer should pay per frame (R18 B-1): each start
  /// runs a synchronous tile copy + premultiply on the UI thread, so
  /// bursts of a hundred-plus starts in one frame hitch. Completions
  /// notify listeners (coalesced per frame), so budgeted consumers chain
  /// the next chunk off the notification and pending tiles always drain.
  ///
  /// 32 (R19-8K): the premultiply now runs in C, so a start is dominated
  /// by the 256KB tile copy — 12/frame left an 8000² full-canvas commit
  /// (1024 tiles) converging over ~85 frames (~1.4s of the fill wall).
  static const int decodeStartBudget = 32;

  /// Starts decoding [tile] once; notifies listeners when the image is ready.
  ///
  /// [staleScope] identifies the logical surface lineage (e.g. a brush frame)
  /// so [latestImageForCoord] never leaks another lineage's artwork.
  void ensureDecoded(BitmapTile tile, {Object? staleScope}) {
    if (_images[tile] != null || _inFlight[tile] != null) {
      return;
    }
    _inFlight[tile] = _inFlightMarker;

    final upload = premultipliedTileUpload(tile);

    ui.decodeImageFromPixels(
      upload.view,
      tile.size,
      tile.size,
      ui.PixelFormat.rgba8888,
      (image) {
        upload.free();
        _images[tile] = image;
        _imageFinalizer.attach(tile, image);
        final scoped = _latestDecodedByScope.remove(staleScope);
        // Re-insert: this scope becomes the most recently used.
        (_latestDecodedByScope[staleScope] =
                scoped ?? <TileCoord, BitmapTile>{})[tile.coord] =
            tile;
        _evictScopesBeyondBudget();
        _scheduleNotify();
      },
    );
  }

  /// ADOPTS an already-decoded [image] as [tile]'s picture — the
  /// promotion round's pen-up handoff.
  ///
  /// The live overlay decoded exactly these premultiplied bytes while the
  /// user drew, and the tile the stroke promotes carries exactly those
  /// straight bytes; re-decoding them at commit was the old pipeline
  /// paying twice for one picture (and the reason the overlay had to
  /// linger through a "settle" window while the second decode landed).
  /// Ownership transfers here: the finalizer retires the image with the
  /// tile, so the caller must NOT dispose it.
  ///
  /// A tile that somehow already has an image keeps it and the incoming
  /// one is retired — never two owners for one image.
  void adoptDecoded(BitmapTile tile, ui.Image image, {Object? staleScope}) {
    if (_images[tile] != null) {
      DeferredImageDisposer.instance.retire(image);
      return;
    }
    // An in-flight decode for this tile would land later and overwrite
    // the entry (leaking this image's ownership), so let it win instead.
    if (_inFlight[tile] != null) {
      DeferredImageDisposer.instance.retire(image);
      return;
    }
    _images[tile] = image;
    _imageFinalizer.attach(tile, image);
    final scoped = _latestDecodedByScope.remove(staleScope);
    (_latestDecodedByScope[staleScope] =
            scoped ?? <TileCoord, BitmapTile>{})[tile.coord] =
        tile;
    _evictScopesBeyondBudget();
  }

  /// Forgets every stale-fallback tile in [scope], so the next paint of a
  /// surface in that scope has nothing to borrow.
  ///
  /// For a lineage whose CONTENT is replaced rather than edited. The
  /// transform float is the case: a new lift makes a surface that is not a
  /// later version of the previous float, it is a different picture, and
  /// letting it borrow drew the previous transform's artwork at the
  /// previous transform's place and size. Emptying the scope at the moment
  /// the content changes says exactly that, and says nothing about the
  /// float's ordinary regenerations — a nudge or a drag release rebuilds
  /// the same picture and SHOULD borrow, which is what an unconditional
  /// opt-out took away.
  ///
  /// Cheaper than a scope per generation, which would be actively harmful:
  /// [retainedScopeLimit] evicts least-recently-used, so a session of
  /// transforms would push out the `(layerId, frameId)` buckets the brush
  /// depends on.
  void resetScope(Object? scope) {
    _latestDecodedByScope.remove(scope);
  }

  void _evictScopesBeyondBudget() {
    while (_latestDecodedByScope.length > retainedScopeLimit) {
      _latestDecodedByScope.remove(_latestDecodedByScope.keys.first);
    }
  }

  bool _notifyScheduled = false;

  /// Coalesces decode-completion notifications to at most ONE per frame: a
  /// big stroke's commit decodes dozens of tiles whose completions land
  /// back to back, and notifying per tile forced a full repaint of every
  /// listening painter per tile — a burst that hitched the START of the
  /// next stroke (R11-⑥). The settling overlay keeps the stroke on screen
  /// through the extra frame of latency. Without a scheduler binding
  /// (headless painter tests) completions notify directly, as before.
  void _scheduleNotify() {
    if (_notifyScheduled) {
      return;
    }
    final binding = _schedulerBindingOrNull();
    if (binding == null) {
      notifyListeners();
      return;
    }
    _notifyScheduled = true;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
    // A completion between frames must still get a frame to notify on.
    binding.ensureVisualUpdate();
  }

  static SchedulerBinding? _schedulerBindingOrNull() {
    try {
      return SchedulerBinding.instance;
    } on FlutterError {
      return null;
    }
  }

  /// Whether every tile of [tiles] has a decoded image ready.
  bool allDecoded(Iterable<BitmapTile> tiles) {
    for (final tile in tiles) {
      if (_images[tile] == null) {
        return false;
      }
    }
    return true;
  }

  /// [tile]'s pixel bytes premultiplied for a raw rgba8888 upload,
  /// staged where `decodeImageFromPixels` can read them DIRECTLY.
  ///
  /// Tile bytes are stored with straight (unpremultiplied) alpha, but the
  /// engine interprets raw rgba8888 uploads as premultiplied. Premultiplies
  /// using Skia's own mul-div-255 rounding so the result matches what Skia
  /// produces when rasterizing straight-alpha colors. Shared with the tiled
  /// surface compose path so every tile upload in the app rounds
  /// identically.
  ///
  /// Returns a buffer the caller must [PremultipliedTileUpload.free] once
  /// the decode has consumed it — the same handoff the live overlay's own
  /// upload already makes, and the reason nothing here lifts the bytes
  /// into a Dart-heap list first.
  ///
  /// That copy WAS the decode start. Measured at the production 256px
  /// tile (same run, same inputs): 58us with the handoff against 385us
  /// with the copy in front of it, 6.6x — and at
  /// [decodeStartBudget] starts a paint, 1.9ms instead of ~8ms of UI
  /// thread. The gap is superlinear in tile size (1.8x at 64KB) because
  /// the copy is not just bytes: it allocates and then discards 256KB of
  /// Dart heap per start, 8MB a paint, which is old-space churn the GC
  /// has to walk.
  static PremultipliedTileUpload premultipliedTileUpload(BitmapTile tile) {
    // R18 A-2a / R19-Z: the fused native kernel reads the tile's NATIVE
    // buffer directly and premultiplies in one pass — byte-identical to
    // the Dart reference below (parity-pinned). The scratch it writes is
    // per-call, so it can be handed to the decoder as-is and released in
    // the callback.
    final native = QaNativeEngine.instance;
    if (native != null) {
      final scratch = tile.readPixels(
        (pointer, _) =>
            native.premultipliedTileScratch(pointer, tile.size * tile.size),
      );
      return PremultipliedTileUpload._(scratch.view, scratch);
    }
    final pixels = tile.pixels;
    for (var offset = 0; offset < pixels.length; offset += 4) {
      final alpha = pixels[offset + 3];
      if (alpha == 255) {
        continue;
      }
      if (alpha == 0) {
        pixels[offset] = 0;
        pixels[offset + 1] = 0;
        pixels[offset + 2] = 0;
        continue;
      }
      pixels[offset] = _mul255Round(pixels[offset], alpha);
      pixels[offset + 1] = _mul255Round(pixels[offset + 1], alpha);
      pixels[offset + 2] = _mul255Round(pixels[offset + 2], alpha);
    }
    // The fallback's list is already the caller's own, so its release is
    // the garbage collector's job.
    return PremultipliedTileUpload._(pixels, null);
  }

  /// Skia's `SkMulDiv255Round`: round(value * alpha / 255) for bytes.
  static int _mul255Round(int value, int alpha) {
    final product = value * alpha + 128;
    return (product + (product >> 8)) >> 8;
  }
}

/// Premultiplied tile bytes staged for ONE `decodeImageFromPixels`, plus
/// the release that goes with them.
///
/// [view] may be a window onto native memory ([BitmapTileImageCache
/// .premultipliedTileUpload] with the engine loaded), which is what keeps
/// a 256KB VM copy out of every decode start. `decodeImageFromPixels`
/// hands the bytes to `ImmutableBuffer.fromUint8List`, which copies them
/// into engine memory during the call itself, so releasing from the
/// decode CALLBACK is safe with room to spare — and releasing any earlier
/// is not.
class PremultipliedTileUpload {
  const PremultipliedTileUpload._(this.view, this._scratch);

  /// The bytes to hand the decoder. Valid until [free].
  final Uint8List view;

  /// Null when [view] is an ordinary Dart list (the no-engine fallback).
  final QaStampScratch? _scratch;

  /// Call from the decode callback, once — never before it fires.
  void free() => _scratch?.free();
}
