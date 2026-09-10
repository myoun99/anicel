import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/sync_image_upload.dart';
import '../../services/straight_rgba_image.dart';
import '../../core/rgba_premultiply.dart';
import '../../models/bitmap_tile.dart';
import '../../models/placed_tile.dart';
import '../../models/tile_coord.dart';
import '../../native/qa_native_engine.dart';
import 'deferred_image_disposal.dart';
import 'tile_predecessors.dart';

/// What has been asked of the engine for one tile that has no picture yet.
///
/// ⛔LANDED IS NOT A VALUE — it is the absence of one, because a landed
/// decode lives in the image map and this only records what is still owed.
/// The two spellings this separates were both 「not in the set」 before
/// 2026-09-09; see [BitmapTileImageCache._decodeAsk] for what that cost.
enum _TileDecodeAsk {
  /// Out with the engine, no answer yet. Everything stands aside for this
  /// one, because it is going to land and overwrite what they would put
  /// there.
  running,

  /// The engine refused it. ⛔NOT a reason to stand aside: nothing is
  /// coming, so the adoption doors are the only way this tile ever gets a
  /// picture. And not a reason to ask again either — a [BitmapTile] is
  /// immutable and `Expando`-keyed, so the ask's identity can never change,
  /// and re-asking on the repaint that this schedules would be a loop with
  /// a frame for a period.
  refused,
}

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

  final Expando<ui.Image> _images = Expando<ui.Image>(
    'bitmapTileImages',
  );

  /// What this cache has been through for one tile's own picture, when it
  /// has no picture yet. Absent means nobody has asked.
  ///
  /// 🚨★★★**ABSENT USED TO MEAN BOTH 「nobody has asked」 AND 「the last ask
  /// was REFUSED」.** This was a `Set`-shaped `Expando` with ONE write and
  /// ZERO clears — `git log -S` finds no commit that ever removed one —
  /// because the marker was cleared nowhere and success only worked by
  /// every reader testing [_images] first. `ui.decodeImageFromPixels` does
  /// not invoke its callback on failure (read in the SDK source), so a
  /// refused tile kept a marker nothing could retire, and was then
  /// unrequestable ([needsDecodeStart], [ensureDecoded]), un-adoptable
  /// ([adoptDecoded]) AND un-uploadable ([adoptSyncUpload]) — a canvas tile
  /// blank for the life of the tile object, that even the in-frame
  /// synchronous upload stood aside for. Downstream, `allDecoded` never
  /// came true, so the settle window's two-second give-up dropped the
  /// stand-in and a tile-shaped patch of the stroke reverted to pre-stroke
  /// pixels — the exact failure the settle machinery exists to prevent.
  final Expando<_TileDecodeAsk> _decodeAsk = Expando<_TileDecodeAsk>(
    'bitmapTileImageDecodes',
  );
  // Deferred, not direct, disposal: the finalizer runs at GC time — pen-up
  // commits allocate heavily and collect right when a replaced tile's image
  // is still referenced by the frame on screen. Disposing it there raced
  // the raster thread and intermittently flashed the tile as a black square
  // for one frame.
  static final Finalizer<ui.Image> _imageFinalizer = Finalizer<ui.Image>(
    DeferredImageDisposer.instance.retire,
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
    DeferredImageDisposer.instance.retire,
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
      _images[tile] == null && _decodeAsk[tile] == null;

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
  void ensureDecoded(PlacedTile placed, {Object? staleScope}) {
    final tile = placed.tile;
    if (_images[tile] != null || _decodeAsk[tile] != null) {
      return;
    }
    _decodeAsk[tile] = _TileDecodeAsk.running;
    unawaited(_decodeInto(placed, staleScope));
  }

  /// 🚨★★★**THE ASK IS GIVEN BACK ON ALL THREE ROADS**, and structurally —
  /// the statement after the `await`, or the `catch`. There is no fourth
  /// way out of this body, which is what makes 「refused」 impossible to
  /// confuse with 「never asked」. ⛔The staging buffer is inside the `try`
  /// on purpose: [premultipliedTileUpload] `malloc`s, so it can throw
  /// BEFORE any decode starts, and that road left a marker too.
  Future<void> _decodeInto(PlacedTile placed, Object? staleScope) async {
    final tile = placed.tile;
    try {
      final upload = premultipliedTileUpload(tile);
      final ui.Image image;
      try {
        image = await uploadRawRgba(
          upload.view,
          width: tile.size,
          height: tile.size,
        );
      } finally {
        // ⚠️No earlier: the bytes may be a window onto native memory, and
        // `ImmutableBuffer.fromUint8List` copies them into engine memory
        // during the call itself. No later either — an in-flight tile
        // holding 256 KB of native staging is the cost this whole handoff
        // exists to avoid paying twice.
        upload.free();
      }
      _decodeAsk[tile] = null;
      _images[tile] = image;
      _imageFinalizer.attach(tile, image);
      // Truth has landed; the stand-in has nothing left to stand in for,
      // and neither has the predecessor it would have been composed from.
      _dropProvisional(tile);
      TilePredecessors.instance.drop(tile);
      final scoped = _latestDecodedByScope.remove(staleScope);
      // Re-insert: this scope becomes the most recently used.
      (_latestDecodedByScope[staleScope] =
              scoped ?? <TileCoord, BitmapTile>{})[placed.coord] =
          tile;
      _evictScopesBeyondBudget();
      _scheduleNotify();
    } on Object catch (error, stack) {
      _decodeAsk[tile] = _TileDecodeAsk.refused;
      // 🚨★★★**AND IT NOTIFIES.** The refused TILE has nothing new to
      // draw, but the pipeline behind it does: starts are budgeted
      // ([decodeStartBudget]) and 「completions notify → repaint → the next
      // chunk starts」 is the ONLY thing that drains the rest. A whole
      // chunk refusing during a transient squeeze would otherwise stop a
      // thousand-tile cel converging until some unrelated widget happened
      // to repaint. ⛔This is not the media viewer's re-ask loop: the
      // refusal is written down FIRST, so the repaint this schedules
      // collects the other tiles and never this one.
      _scheduleNotify();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'anicel',
          context: ErrorDescription(
            'decoding a ${tile.size}px canvas tile at ${placed.coord}',
          ),
        ),
      );
    }
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
  void adoptDecoded(
    PlacedTile placed,
    ui.Image image, {
    Object? staleScope,
  }) {
    final tile = placed.tile;
    if (_images[tile] != null) {
      DeferredImageDisposer.instance.retire(image);
      return;
    }
    // An in-flight decode for this tile would land later and overwrite
    // the entry (leaking this image's ownership), so let it win instead.
    //
    // 🚨RUNNING, not 「asked at all」. A REFUSED ask is never going to land,
    // so standing aside for one threw away the pen-up handoff's image — the
    // very picture the live overlay had already decoded from these exact
    // bytes — and left the tile blank with nothing left to fill it. That is
    // this guard's own reasoning read correctly: it is about a decode that
    // WILL arrive.
    if (_decodeAsk[tile] == _TileDecodeAsk.running) {
      DeferredImageDisposer.instance.retire(image);
      return;
    }
    // 🚨AND THE REFUSAL IS RETIRED WITH IT. [_TileDecodeAsk]'s headline says
    // landed is the ABSENCE of a value; adoption is the other way a tile
    // lands, and it left a `refused` entry standing beside a real picture.
    // Harmless only because every reader tests [_images] first — which is
    // the sentence [_decodeAsk] names as the cause of the original bug, so
    // resting on it twice is how the same defect comes back. Found by the
    // 2026-09-09 audit.
    _decodeAsk[tile] = null;
    _images[tile] = image;
    _imageFinalizer.attach(tile, image);
    // An adopted picture IS the truth (the overlay decoded exactly these
    // bytes), so it retires a stand-in just as a decode would — and the
    // predecessor with it.
    _dropProvisional(tile);
    TilePredecessors.instance.drop(tile);
    final scoped = _latestDecodedByScope.remove(staleScope);
    (_latestDecodedByScope[staleScope] =
            scoped ?? <TileCoord, BitmapTile>{})[placed.coord] =
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
  ui.Image? adoptSyncUpload(PlacedTile placed, {Object? staleScope}) {
    final tile = placed.tile;
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
    // stands aside for one. 🚨RUNNING only: a refused ask is not coming,
    // and this synchronous upload is the one door that can still fill the
    // tile inside the frame.
    if (_decodeAsk[tile] == _TileDecodeAsk.running) {
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
    adoptDecoded(placed, image, staleScope: staleScope);
    return _images[tile];
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
    premultiplyRgbaInPlace(pixels);
    // The fallback's list is already the caller's own, so its release is
    // the garbage collector's job.
    return PremultipliedTileUpload._(pixels, null);
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
