import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../core/sync_image_upload.dart';
import '../../models/bitmap_tile.dart';
import '../../models/tile_roll.dart';
import '../../native/premultiplied_copy.dart';
import 'chained_picture.dart';
import 'deferred_image_disposal.dart';
import 'tile_pages.dart';

/// The pictures of immutable [BitmapTile]s, keyed by tile identity, for
/// display.
///
/// This is derived render data only — never source of truth. Tiles are
/// immutable and structurally shared across [BitmapSurface] versions, so
/// the tile object's identity is a stable cache key: an unchanged tile
/// keeps its picture across surface updates, and a changed tile is a new
/// object whose picture is made once.
///
/// 🚨★★★A TILE'S PICTURE IS MADE THE MOMENT IT IS NEEDED, FROM ITS OWN
/// BYTES, INSIDE THE CALL ([pictureFor] — the one door, [pictureOf],
/// synchronous on every engine since 2026-09-17). There is no decode in
/// flight, no picture "not ready yet", and therefore nothing that has to
/// stand in for one: not the previous tile's picture at the coordinate,
/// not a composition from the predecessor, not a per-pixel frame, not a
/// blank. Every one of those was a way of waiting, and the whole
/// stale-tile family — the stroke's last tiles missing at pen-up, a commit
/// arriving tile by tile, a transform's landing half absent, an undo's
/// first frame blank — was the wait made visible.
///
/// Where the engine writes pages, the bytes go into a slot of one
/// ([TilePages]) rather than a texture of the tile's own — the same
/// premultiplied bytes, in the same call, drawn the same.
///
/// The other way a tile gets its picture is [adoptDecoded]: pen-up hands
/// over the picture the live overlay already made of exactly these bytes,
/// so a stroke's tiles are pictured once, not twice.
///
/// Entries never need manual eviction: the [Expando] releases them with
/// the tile, and a [Finalizer] lets the picture go afterwards. The
/// picture budget lets pictures go EARLY ([releasePicture]) when the device
/// cannot hold every one; a tile asked for again is simply pictured again.
class BitmapTileImageCache {
  BitmapTileImageCache({TileRoll? pictured, TilePages? pages})
    : pictured = pictured ?? TileRoll(),
      pages = pages ?? TilePages.instance;

  /// Shared instance used by the display painter. A render cache, not app
  /// state: it holds no editing data and only accelerates repaints.
  static final BitmapTileImageCache instance = BitmapTileImageCache();

  /// The roll of every tile given a picture here — the one way the pictures
  /// held can be walked ([TilePictureBudget]), since [_pictures] cannot be.
  final TileRoll pictured;

  /// Where the pictures this makes lie, where the engine writes pages.
  final TilePages pages;

  final Expando<TilePicture> _pictures = Expando<TilePicture>(
    'bitmapTilePictures',
  );

  // Deferred, not direct, disposal: the finalizer runs at GC time — pen-up
  // commits allocate heavily and collect right when a replaced tile's image
  // is still referenced by the frame on screen. Disposing it there raced
  // the raster thread and intermittently flashed the tile as a black square
  // for one frame.
  static final Finalizer<TilePicture> _pictureFinalizer =
      Finalizer<TilePicture>(_release);

  /// Bytes of every tile picture alive right now, every cache's — for the
  /// memory census.
  ///
  /// 🚨C-ipad-crash (2026-09-11): on a phone these are GPU textures, and
  /// the census had no row for them, so the whole share read as engine
  /// overhead. Taken in [_hold] and let go in [_release], the only two
  /// places either happens — a picture's chain with it ([pictureBytesOf]);
  /// the pages pictures lie in count whole ([TilePages.liveBytes]).
  static int get liveImageBytes => _liveImageBytes + TilePages.liveBytes;
  static int _liveImageBytes = 0;

  static void _hold(TilePicture picture) {
    if (picture is OwnTilePicture) {
      _liveImageBytes += pictureBytesOf(picture.image);
    }
  }

  static void _release(TilePicture picture) {
    switch (picture) {
      case OwnTilePicture(:final image):
        _liveImageBytes -= pictureBytesOf(image);
        DeferredImageDisposer.instance.retire(image);
      case final TileSlot slot:
        slot.release();
    }
  }

  /// The picture [tile] already has, or `null` — nothing is made here.
  /// Callers deciding what to DRAW want [pictureFor].
  TilePicture? heldFor(BitmapTile tile) => _pictures[tile];

  /// [tile]'s picture: the one it has, or the one made now from its own
  /// bytes through the door and kept — the ONE way a committed tile gets a
  /// picture besides the pen-up handoff ([adoptDecoded]).
  ///
  /// 🪦Until 2026-09-17 this and its siblings took the tile WITH its
  /// coordinate, because a picture was also filed under where it sat — the
  /// coordinate fallback's bucket. Nothing is looked up by coordinate any
  /// more, so the cache does not ask where a tile is.
  TilePicture pictureFor(BitmapTile tile) {
    final existing = _pictures[tile];
    if (existing != null) {
      return existing;
    }
    final bytes = _TilePictureBytes(tile);
    final picture = pages.write(bytes) ?? OwnTilePicture(pictureOf(bytes));
    _own(tile, picture);
    return picture;
  }

  /// [tile]'s picture as a screen drawing it REDUCED samples it — carrying
  /// the engine's chain ([chainedPictureOf]): the one it has where that
  /// carries one, else that one remade with it IN ITS PLACE. Still one
  /// picture a tile; a tile only ever drawn at 100% never pays the chain.
  /// A page carries no chain, so a tile in a slot drawn reduced leaves its
  /// slot for a picture of its own.
  ui.Image chainedPictureFor(BitmapTile tile) {
    final held = _pictures[tile];
    if (held is OwnTilePicture && carriesChain(held.image)) {
      return held.image;
    }
    final from = held ?? OwnTilePicture(pictureOfTile(tile));
    final chained = chainedPictureOf(
      from.image,
      source: from is TileSlot ? from.source : null,
    );
    if (held != null) {
      releasePicture(tile);
    } else {
      DeferredImageDisposer.instance.retire(from.image);
    }
    _own(tile, OwnTilePicture(chained));
    return chained;
  }

  /// A fresh picture of [tile]'s bytes through the door — the caller's to
  /// keep and to dispose (the live overlay pictures a fill's result tiles
  /// this way, then hands them over at the commit).
  static ui.Image pictureOfTile(BitmapTile tile) =>
      pictureOf(_TilePictureBytes(tile));

  /// ADOPTS an already-made [image] as [tile]'s picture — the pen-up
  /// handoff.
  ///
  /// The live overlay pictured exactly these bytes while the user drew, and
  /// the tile the stroke promotes carries exactly those straight bytes;
  /// picturing them again at the commit was the old pipeline paying twice
  /// for one picture. Ownership transfers here: the finalizer retires the
  /// image with the tile, so the caller must NOT dispose it.
  ///
  /// A tile that somehow already has a picture keeps it and the incoming
  /// one is retired — never two owners for one image.
  void adoptDecoded(BitmapTile tile, ui.Image image) {
    if (_pictures[tile] != null) {
      DeferredImageDisposer.instance.retire(image);
      return;
    }
    _own(tile, OwnTilePicture(image));
  }

  void _own(BitmapTile tile, TilePicture picture) {
    _pictures[tile] = picture;
    _pictureFinalizer.attach(tile, picture, detach: tile);
    _hold(picture);
    pictured.hold(tile);
  }

  /// Lets [tile]'s picture go while the tile itself lives on — the door
  /// undo-held-tile-pictures stage 2 needed, where a picture used to live
  /// exactly as long as its tile. Asked for again, it is made again like
  /// the picture of any tile that has none.
  ///
  /// Detached first: without it the finalizer lets the same picture go a
  /// second time when the tile is eventually collected. An image is retired
  /// through the deferred disposer like every picture here.
  void releasePicture(BitmapTile tile) {
    final picture = _pictures[tile];
    if (picture == null) {
      return;
    }
    _pictures[tile] = null;
    _pictureFinalizer.detach(tile);
    _release(picture);
  }

  /// [tile]'s pixel bytes premultiplied for a raw rgba8888 upload, staged
  /// where the engine can read them DIRECTLY.
  ///
  /// Tile bytes are stored with straight (unpremultiplied) alpha, but the
  /// engine interprets raw rgba8888 uploads as premultiplied. Premultiplies
  /// using Skia's own mul-div-255 rounding so the result matches what Skia
  /// produces when rasterizing straight-alpha colors — which is what makes
  /// the door's two roads one picture.
  ///
  /// Returns a buffer the caller must [PremultipliedTileUpload.free] once
  /// the upload has consumed it — the reason nothing here lifts the bytes
  /// into a Dart-heap list first.
  ///
  /// That copy WAS the cost of a picture. Measured at the production 256px
  /// tile (same run, same inputs): 58us with the handoff against 385us
  /// with the copy in front of it, 6.6x. The gap is superlinear in tile
  /// size (1.8x at 64KB) because the copy is not just bytes: it allocates
  /// and then discards 256KB of Dart heap per picture, which is old-space
  /// churn the GC has to walk.
  static PremultipliedTileUpload premultipliedTileUpload(BitmapTile tile) {
    // R18 A-2a / R19-Z: the fused native kernel reads the tile's NATIVE
    // buffer directly and premultiplies in one pass — byte-identical to
    // the app's law (`premultiplyRgbaInPlace`, parity-pinned). The block
    // it writes is per-call, so it can be handed to the engine as-is and
    // released right after.
    // ↩️Where no C engine was loaded the tile's bytes were lifted into a
    // list and the law premultiplied them there; the kernel is the engine
    // library's now, in every isolate and every build (C ABI 83).
    final pixelCount = tile.size * tile.size;
    return tile.readPixels(
      (straight, _) => PremultipliedTileUpload._of(straight, pixelCount),
    );
  }
}

/// A [BitmapTile] as the door reads it: its own straight bytes as they lie
/// (a window onto native memory, valid inside the read), or its
/// premultiplied form staged for the upload and released right after.
class _TilePictureBytes implements PictureBytes {
  _TilePictureBytes(this.tile);

  final BitmapTile tile;

  @override
  int get width => tile.size;

  @override
  int get height => tile.size;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) =>
      tile.readPixels((_, view) => use(view));

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    final upload = BitmapTileImageCache.premultipliedTileUpload(tile);
    try {
      return use(upload.view);
    } finally {
      // ⚠️No earlier: the bytes are a window onto native memory, and
      // the engine copies them into its own memory during the upload
      // itself. No later either — a staged 256 KB the frame keeps holding
      // is the cost this handoff exists to avoid paying twice.
      upload.free();
    }
  }
}

/// Premultiplied tile bytes staged for ONE upload, plus the release that
/// goes with them.
///
/// [view] is a window onto native memory, which is what keeps a 256KB VM
/// copy out of every picture. The engine copies the bytes into its own
/// memory during the upload call itself, so releasing right after it
/// returns is safe — and releasing any earlier is not.
class PremultipliedTileUpload {
  PremultipliedTileUpload._(this._block, int byteLength)
    : view = _block.asTypedList(byteLength) {
    _live += 1;
  }

  /// [pixelCount] straight pixels at [straight], premultiplied into a
  /// block of their own.
  factory PremultipliedTileUpload._of(Pointer<Uint8> straight, int pixelCount) {
    final block = malloc<Uint8>(pixelCount * 4);
    premultiplyRgbaCopy(block, straight, pixelCount);
    return PremultipliedTileUpload._(block, pixelCount * 4);
  }

  /// The bytes to hand the engine. Valid until [free].
  final Uint8List view;

  final Pointer<Uint8> _block;

  /// Call once the upload has consumed [view] — never before.
  ///
  /// ⛔**NOT in a decode callback.** The staging's own note said so once,
  /// and it was the bug: `ui.decodeImageFromPixels` does not invoke its
  /// callback when it REFUSES, so a failed decode leaked the whole block.
  /// Every call site was moved to a `finally` (see [debugLiveCount], and
  /// the note beside the one in `straight_rgba_image.dart` — "THE
  /// `finally` IS THE FIX") and the sentence outlived them, telling the
  /// next reader to put it back.
  void free() {
    malloc.free(_block);
    _live -= 1;
  }

  static int _live = 0;

  /// How many of these are alive right now.
  ///
  /// 🧪★★★**A LEAK HERE IS INVISIBLE TO EVERYTHING ELSE.** This is a bare
  /// `malloc` with no `NativeFinalizer` behind it, so an unfreed block is
  /// not reclaimed by the GC, does not show up in Dart heap numbers, and
  /// costs a whole tile — 256 KB at a 256 px tile. ↩️Four call sites freed
  /// such a block inside a decode CALLBACK, which
  /// `ui.decodeImageFromPixels` does not invoke when it refuses; every one
  /// was moved to a `finally`, and without a count the difference between
  /// those two shapes is something no test can see. Three of the four went
  /// with the C brush's stamps (C ABI 80); the one that stays is a tile's
  /// picture ([BitmapTileImageCache.pictureFor]), held by
  /// a_tile_upload_is_the_apps_premultiply_test.
  ///
  /// ⛔Read it around an operation, never as an absolute: this is a
  /// process-wide counter and other work holds blocks at the same time.
  @visibleForTesting
  static int get debugLiveCount => _live;
}
