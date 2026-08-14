import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/sync_image_upload.dart';
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

  /// Bumped whenever this cache tells its listeners something moved — one
  /// int that answers "did anything I hold change since you last looked".
  ///
  /// 🚨★★★A CACHE OVER THIS MUST ASK ONE CHEAP QUESTION, NOT N. (v)'s
  /// composite buffer needs to know when the pixels under it moved, and a
  /// decode ARRIVING is the everyday case — the bytes were always there,
  /// the pixels on screen were not. Walking every tile and hashing its
  /// image identity answers that, and costs a lookup per tile PER PAINT for
  /// a cache that may not even hit: measured, that walk never produced a
  /// stable key in a widget test, so the buffer paid the walk and missed
  /// anyway ([[cache-what-can-say-where-it-changed]]).
  ///
  /// ⛔It rides [notifyListeners] because those ARE the moments this cache
  /// admits it changed. Anything that moves an image without notifying is
  /// already broken for every listener, not just for this counter.
  int get revision => _revision;
  int _revision = 0;

  @override
  void notifyListeners() {
    _revision += 1;
    super.notifyListeners();
  }

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

  /// SYNTHESIZED stand-ins: the picture a tile shows while its own decode
  /// is still in flight, made from pictures already on the GPU rather than
  /// borrowed from a previous generation at the same coordinate.
  ///
  /// Kept in its own slot rather than written into [_images] on purpose —
  /// a stand-in must NOT stop the real decode, and it must not become the
  /// tile's permanent picture. Composing `srcOver(pre, ink)` is the same
  /// operation the screen was already performing while the user drew, but
  /// it is not byte-identical to what the commit kernel produced: the
  /// kernel blends in straight alpha and premultiplies once, the
  /// composition premultiplies both operands first. Measured worst case is
  /// TWO channel steps, at middling alpha on both operands
  /// (`tile_image_sync_compose_parity_test`). Adopting that outright would
  /// pin an off-by-two picture forever on those tiles.
  final Expando<ui.Image> _provisional = Expando<ui.Image>(
    'bitmapTileProvisionalImages',
  );

  /// Detached explicitly when the real decode replaces a stand-in, so the
  /// image is retired exactly once.
  static final Finalizer<ui.Image> _provisionalFinalizer = Finalizer<ui.Image>(
    (image) => DeferredImageDisposer.instance.retire(image),
  );

  /// The decoded image for [tile], or `null` while the decode is pending.
  ///
  /// TRUTH only. Callers deciding what to DRAW want [displayImageFor];
  /// callers deciding what to decode, adopt or hand to a later generation
  /// want this one.
  ui.Image? imageFor(BitmapTile tile) => _images[tile];

  /// What the painter should DRAW for [tile]: its own decoded picture if
  /// that has landed, otherwise a synthesized stand-in.
  ///
  /// Both are pictures OF THIS TILE. That is the whole difference from
  /// [latestImageForCoord], which answers with a different tile's picture
  /// and is the reason a stroke could land and show the artwork that was
  /// there before it.
  ui.Image? displayImageFor(BitmapTile tile) =>
      _images[tile] ?? _provisional[tile];

  /// Whether the stand-in SLOT for [tile] is occupied.
  ///
  /// ⚠️ Deliberately says nothing about `_images`. Written as
  /// "showing a stand-in" (`_images[tile] == null && ...`) it reads better
  /// and is useless: once the real picture lands that expression is false
  /// whether or not the stand-in was actually retired, so a test built on
  /// it passes with the retirement DELETED — verified by mutation, which
  /// is the only reason this comment exists. The leak is about ownership,
  /// so the observable has to be about ownership too.
  bool hasProvisional(BitmapTile tile) => _provisional[tile] != null;

  /// Gives [tile] a synthesized stand-in until its own decode lands.
  ///
  /// Ownership transfers: the image is retired when the real decode
  /// replaces it, or with the tile if no decode ever comes. The caller must
  /// NOT dispose it.
  ///
  /// Does nothing if the tile already has a real picture (nothing to stand
  /// in for) or already has a stand-in (the first one was composed from the
  /// same operands; a second is redundant). Deliberately does NOT touch
  /// [_latestDecodedByScope]: a stand-in is not a truthful predecessor for
  /// some later generation to borrow, and seeding it there would put the
  /// off-by-two into a lineage that outlives it.
  void putProvisional(BitmapTile tile, ui.Image image) {
    if (_images[tile] != null || _provisional[tile] != null) {
      DeferredImageDisposer.instance.retire(image);
      return;
    }
    _provisional[tile] = image;
    _provisionalFinalizer.attach(tile, image, detach: tile);
  }

  /// Retires [tile]'s stand-in, if it has one. Called the moment its real
  /// picture lands.
  void _dropProvisional(BitmapTile tile) {
    final provisional = _provisional[tile];
    if (provisional == null) {
      return;
    }
    _provisional[tile] = null;
    // Detach first: without it the finalizer retires the same image a
    // second time when the tile is eventually collected.
    _provisionalFinalizer.detach(tile);
    DeferredImageDisposer.instance.retire(provisional);
  }

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
        // Truth has landed; the stand-in has nothing left to stand in for.
        _dropProvisional(tile);
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
    // An adopted picture IS the truth (the overlay decoded exactly these
    // bytes), so it retires a stand-in just as a decode would.
    _dropProvisional(tile);
    final scoped = _latestDecodedByScope.remove(staleScope);
    (_latestDecodedByScope[staleScope] =
            scoped ?? <TileCoord, BitmapTile>{})[tile.coord] =
        tile;
    _evictScopesBeyondBudget();
  }

  /// Uploads [tile]'s own bytes synchronously and adopts the result as
  /// TRUTH; null where the engine cannot ([syncImageUploadSupported] —
  /// Impeller only), or where the tile already has a picture or a decode
  /// in flight.
  ///
  /// Truth, not a stand-in: these are the same premultiplied bytes
  /// [ensureDecoded] would have handed the asynchronous decoder, so the
  /// picture is the tile's own and there is nothing to replace later.
  /// That is the difference from [putProvisional], and it is why this
  /// retires a stand-in rather than sitting beside one.
  ///
  /// The scratch is freed as soon as the call returns; see
  /// [uploadImageSync] for why that is safe and what breaks if it stops
  /// being.
  ui.Image? adoptSyncUpload(BitmapTile tile, {Object? staleScope}) {
    // FIRST, and it is a cached bool. On Skia this method is called at
    // every undrawable coordinate of every paint and must cost exactly
    // that much; the Expando lookups below would otherwise be paid on a
    // machine that can never use their answer.
    if (!syncImageUploadSupported) {
      return null;
    }
    final existing = _images[tile];
    if (existing != null) {
      return existing;
    }
    // An in-flight decode would land later and overwrite the entry,
    // leaking this image's ownership — the same reason [adoptDecoded]
    // stands aside for one.
    if (_inFlight[tile] != null) {
      return null;
    }
    final upload = premultipliedTileUpload(tile);
    final ui.Image? image;
    try {
      image = uploadImageSync(upload.view, tile.size, tile.size);
    } finally {
      upload.free();
    }
    if (image == null) {
      return null;
    }
    adoptDecoded(tile, image, staleScope: staleScope);
    return _images[tile];
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

  /// Forgets [coords] in [scope] — the surgical [resetScope], for content
  /// removed at KNOWN coordinates while the rest of the lineage stayed put.
  ///
  /// A lift is the case. It commits an erase, so the cel's tiles at the
  /// lifted coordinates are new, empty objects with no image; the bucket
  /// still holds the PRE-erase tiles, and the painter answers with them —
  /// drawing the artwork in its old place while the float draws it in its
  /// new one. Emptying the whole scope would blank the rest of the cel,
  /// which did not move.
  ///
  /// ⚠️ Only for coordinates the removal took WHOLE. Where something
  /// survives at a coordinate, the pre-change tile is still the closest
  /// truth available and dropping it trades a stale pixel for no pixel.
  ///
  /// Notifies: forgetting changes what the next paint draws, and nothing
  /// else here would mark the painters dirty.
  void invalidateCoords(Object? scope, Iterable<TileCoord> coords) {
    final scoped = _latestDecodedByScope[scope];
    if (scoped == null || scoped.isEmpty) {
      return;
    }
    var removed = false;
    for (final coord in coords) {
      if (scoped.remove(coord) != null) {
        removed = true;
      }
    }
    if (!removed) {
      return;
    }
    if (scoped.isEmpty) {
      _latestDecodedByScope.remove(scope);
    }
    _scheduleNotify();
  }

  /// Gives [scope] a starting point: for each entry, the coordinate's
  /// stale-fallback becomes that already-decoded tile.
  ///
  /// The counterpart of [resetScope], for a lineage whose new content is
  /// not new PIXELS. A transform's float is built from a lift, and a lift
  /// is a copy of what was already on screen — so where the lift took a
  /// coordinate whole, the surface it copied from is a truthful
  /// predecessor and the float can draw immediately instead of waiting a
  /// decode round with nothing to show. Without it a fresh float paints
  /// four tiles and no more.
  ///
  /// ⚠️ "Where the lift took the coordinate WHOLE" is the caller's
  /// obligation and it is not a detail. Seeding a coordinate the lift only
  /// partly took would put pixels in the float that the user did not
  /// select, and the float MOVES — it would carry its neighbours along.
  /// That is the same lie as giving the float the base's scope outright.
  ///
  /// Entries with no decoded image are skipped. Nothing here takes
  /// ownership: the tile is held exactly the way [ensureDecoded] holds it,
  /// and [resetScope] lets go of it the same way.
  void seedScope(Object? scope, Map<TileCoord, BitmapTile> tiles) {
    if (tiles.isEmpty) {
      return;
    }
    final scoped = _latestDecodedByScope.remove(scope);
    final bucket = scoped ?? <TileCoord, BitmapTile>{};
    for (final entry in tiles.entries) {
      if (_images[entry.value] == null) {
        continue;
      }
      bucket[entry.key] = entry.value;
    }
    if (bucket.isEmpty) {
      return;
    }
    // Re-inserted last, so a seeded scope is the most recently used.
    _latestDecodedByScope[scope] = bucket;
    _evictScopesBeyondBudget();
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
