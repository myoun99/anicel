import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/sync_image_upload.dart';
import '../../core/rgba_premultiply.dart';
import '../../models/bitmap_tile.dart';
import '../../native/qa_native_engine.dart';
import 'deferred_image_disposal.dart';
import 'pictured_tiles.dart';

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
/// The other way a tile gets its picture is [adoptDecoded]: pen-up hands
/// over the picture the live overlay already made of exactly these bytes,
/// so a stroke's tiles are pictured once, not twice.
///
/// Entries never need manual eviction: the [Expando] releases them with
/// the tile, and a [Finalizer] disposes the picture afterwards. The
/// picture budget lets pictures go EARLY ([releasePicture]) when the device
/// cannot hold every one; a tile asked for again is simply pictured again.
class BitmapTileImageCache {
  BitmapTileImageCache({PicturedTiles? pictured})
    : pictured = pictured ?? PicturedTiles.instance;

  /// Shared instance used by the display painter. A render cache, not app
  /// state: it holds no editing data and only accelerates repaints.
  static final BitmapTileImageCache instance = BitmapTileImageCache();

  /// The roll of every tile given a picture here — the one way the pictures
  /// held can be walked ([TilePictureBudget]), since [_images] cannot be.
  final PicturedTiles pictured;

  final Expando<ui.Image> _images = Expando<ui.Image>(
    'bitmapTileImages',
  );

  // Deferred, not direct, disposal: the finalizer runs at GC time — pen-up
  // commits allocate heavily and collect right when a replaced tile's image
  // is still referenced by the frame on screen. Disposing it there raced
  // the raster thread and intermittently flashed the tile as a black square
  // for one frame.
  static final Finalizer<ui.Image> _imageFinalizer = Finalizer<ui.Image>(
    _release,
  );

  /// Bytes of every tile picture alive right now, every cache's — for the
  /// memory census.
  ///
  /// 🚨C-ipad-crash (2026-09-11): on a phone these are GPU textures, and
  /// the census had no row for them, so the whole share read as engine
  /// overhead. Taken in [_hold] and let go in [_release], the only two
  /// places either happens.
  static int get liveImageBytes => _liveImageBytes;
  static int _liveImageBytes = 0;

  static void _hold(ui.Image image) =>
      _liveImageBytes += image.width * image.height * 4;

  static void _release(ui.Image image) {
    _liveImageBytes -= image.width * image.height * 4;
    DeferredImageDisposer.instance.retire(image);
  }

  /// The picture [tile] already has, or `null` — nothing is made here.
  /// Callers deciding what to DRAW want [pictureFor].
  ui.Image? imageFor(BitmapTile tile) => _images[tile];

  /// [tile]'s picture: the one it has, or the one made now from its own
  /// bytes through the door and kept — the ONE way a committed tile gets a
  /// picture besides the pen-up handoff ([adoptDecoded]).
  ///
  /// 🪦Until 2026-09-17 this and its siblings took the tile WITH its
  /// coordinate, because a picture was also filed under where it sat — the
  /// coordinate fallback's bucket. Nothing is looked up by coordinate any
  /// more, so the cache does not ask where a tile is.
  ui.Image pictureFor(BitmapTile tile) {
    final existing = _images[tile];
    if (existing != null) {
      return existing;
    }
    final image = pictureOfTile(tile);
    _own(tile, image);
    return image;
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
    if (_images[tile] != null) {
      DeferredImageDisposer.instance.retire(image);
      return;
    }
    _own(tile, image);
  }

  void _own(BitmapTile tile, ui.Image image) {
    _images[tile] = image;
    _imageFinalizer.attach(tile, image, detach: tile);
    _hold(image);
    pictured.hold(tile);
  }

  /// Lets [tile]'s picture go while the tile itself lives on — the door
  /// undo-held-tile-pictures stage 2 needed, where a picture used to live
  /// exactly as long as its tile. Asked for again, it is made again like
  /// the picture of any tile that has none.
  ///
  /// Detached first: without it the finalizer retires the same image a
  /// second time when the tile is eventually collected. Retired through
  /// the deferred disposer like every picture here.
  void releasePicture(BitmapTile tile) {
    final image = _images[tile];
    if (image == null) {
      return;
    }
    _images[tile] = null;
    _imageFinalizer.detach(tile);
    _release(image);
  }

  /// [tile]'s pixel bytes premultiplied for a raw rgba8888 upload, staged
  /// where the engine can read them DIRECTLY.
  ///
  /// Tile bytes are stored with straight (unpremultiplied) alpha, but the
  /// engine interprets raw rgba8888 uploads as premultiplied. Premultiplies
  /// using Skia's own mul-div-255 rounding so the result matches what Skia
  /// produces when rasterizing straight-alpha colors — which is what makes
  /// the door's two roads one picture. Shared with the tiled surface
  /// compose path so every tile upload in the app rounds identically.
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
    // the Dart reference below (parity-pinned). The scratch it writes is
    // per-call, so it can be handed to the engine as-is and released
    // right after.
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
      // ⚠️No earlier: the bytes may be a window onto native memory, and
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
/// [view] may be a window onto native memory ([BitmapTileImageCache
/// .premultipliedTileUpload] with the engine loaded), which is what keeps
/// a 256KB VM copy out of every picture. The engine copies the bytes into
/// its own memory during the upload call itself, so releasing right after
/// it returns is safe — and releasing any earlier is not.
class PremultipliedTileUpload {
  const PremultipliedTileUpload._(this.view, this._scratch);

  /// The bytes to hand the engine. Valid until [free].
  final Uint8List view;

  /// Null when [view] is an ordinary Dart list (the no-engine fallback).
  final QaStampScratch? _scratch;

  /// Call once the upload has consumed [view] — never before.
  void free() => _scratch?.free();
}
