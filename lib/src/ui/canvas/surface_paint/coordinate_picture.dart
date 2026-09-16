part of '../bitmap_surface_painter.dart';

/// 🚨★★★THE ONE LAW OF WHAT A COORDINATE SHOWS (유저 절대규칙 2026-09-17:
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」). Every coordinate of the
/// surface shows ONE picture right now, decided here and nowhere else:
/// level 0 draws it ([paint]) and every level above is made from it
/// ([TilePyramid], through [_LevelBlocks]), so the screen shows the same
/// bytes at every zoom and at every moment of a stroke — and nothing that
/// draws a coordinate gets to decide differently.
///
/// 🚨A collaborator of `_SurfacePaintPass`, one per paint like the pass
/// itself; it spends the paint's rations (uploads, compositions, the pixel
/// fallback) through `_pass`.
class _CoordinatePicture {
  _CoordinatePicture(this._pass);

  final _SurfacePaintPass _pass;

  BitmapSurfacePainter get _painter => _pass._painter;

  /// What [coord] shows, in order of who owns the pixels: the live
  /// stroke's result tile where the overlay replaces the coordinate (it
  /// already holds the committed pixels blended with the stroke) — or,
  /// once the stroke is SETTLING, the committed tile that has its OWN
  /// picture, because then the commit has landed and the overlay is at
  /// best a revision behind it; the held pre-stroke tile while a landing
  /// settles; else the committed tile's own picture, uploaded now within
  /// the ration where the engine can, a stand-in composed from its
  /// predecessor, or the coordinate's latest picture.
  ///
  /// `key` is what the answer was made from — the tile object when the
  /// picture is that tile's own truth (a truth key survives its picture's
  /// eviction), the picture object when something else stands at the
  /// coordinate — and it is what a level tile is keyed by. `picture` is
  /// null when the coordinate has bytes but no picture yet (a decode still
  /// in flight, past the ration; level 0 then draws the tile's pixels
  /// within the pixel budget), and the whole answer is null when the
  /// coordinate shows nothing.
  ///
  /// [withPicture] false asks only for the key — no upload, no
  /// composition — which is all a kept level tile needs to know it still
  /// stands.
  ({Object key, ui.Image? picture})? of(
    TileCoord coord, {
    required bool withPicture,
  }) {
    final cache = _painter.tileImageCache;
    final tile = _painter.surface.tileAt(coord);
    final overlay = _pass._overlay;
    final overlayImage = overlay != null && _pass._overlayReplacesCoords
        ? overlay.tileImages[coord]
        : null;
    if (overlayImage != null) {
      // The invariant that makes preferring the committed tile truthful
      // rather than hopeful: pictures are keyed by tile OBJECT, a promoted
      // tile is a fresh object, and only two things can give it one — a
      // decode of its own bytes, or an adoption the handoff already
      // revision-matched. There is no third path, so a picture here is
      // always the final picture.
      //
      // ⚠️ `imageFor`, deliberately: a stand-in WOULD be a third path and
      // it is the weaker picture here. The overlay tile this would
      // displace holds the commit's own bytes exactly, so a composed
      // approximation must never take its place — the stand-in exists for
      // coordinates that have no such answer.
      final settled = overlay!.settling && tile != null
          ? cache.imageFor(tile)
          : null;
      if (settled != null) {
        return (key: tile!, picture: settled);
      }
      return (key: overlayImage, picture: overlayImage);
    }
    final hold = _pass._settleHold;
    if (hold != null && hold.containsKey(coord)) {
      final preTile = hold[coord];
      if (preTile == null) {
        return null;
      }
      return (key: preTile, picture: cache.imageFor(preTile));
    }
    if (tile == null) {
      return null;
    }
    final truth = cache.imageFor(tile);
    if (truth != null) {
      return (key: tile, picture: truth);
    }
    if (!withPicture) {
      return (
        key:
            cache.displayImageFor(tile) ??
            cache.latestImageForCoord(coord, scope: _painter.staleScope) ??
            tile,
        picture: null,
      );
    }
    final placed = (coord: coord, tile: tile);
    var image = _ownOrUploadedPicture(placed);
    if (image != null) {
      // An upload made it the tile's own truth; a stand-in stays a picture
      // that is not the tile's.
      return (key: cache.imageFor(tile) != null ? tile : image, picture: image);
    }
    // 🚨★★★A KNOWN PREDECESSOR FORBIDS THE COORDINATE FALLBACK. The tile
    // the commit replaced, plus the bytes that differ, is exact whichever
    // way the edit went; the coordinate fallback is the last picture
    // DECODED here, and for an edit that removed ink that is the removed
    // ink — F-68 ①②③, every one. So a tile whose commit announced its
    // predecessor composes from it, and when that does not fit this
    // paint's budget it falls to the per-pixel path (exact, four a paint)
    // and then to NOTHING — a blank tile for a frame is a gap, the old
    // picture is a lie, and only one of those was a bug report. The
    // coordinate fallback remains for tiles nobody announced: an import,
    // a cold activation — content that ADDS, where it was always right.
    //
    // What makes the coordinate fallback "slightly stale" rather than a
    // guess is the SCOPE: it must name a lineage in which this
    // coordinate's last decode really is an older version of this tile. A
    // surface whose content gets replaced empties its scope at that moment
    // instead of borrowing across the replacement.
    final predecessor = TilePredecessors.instance.of(tile);
    image = predecessor != null
        ? _composeFromPredecessor(placed, predecessor)
        : cache.latestImageForCoord(coord, scope: _painter.staleScope);
    return (key: image ?? tile, picture: image);
  }

  /// Draws what [coord] shows ([of]) at level 0: its picture, or — a
  /// coordinate with bytes and no picture yet — the tile's pixels,
  /// unbudgeted for a held pre-stroke tile (the hold is a few tiles and
  /// must not blink), within the pixel budget for a committed one, and
  /// marked unpainted past it.
  void paint(TileCoord coord) {
    final now = of(coord, withPicture: true);
    if (now == null) {
      return;
    }
    final picture = now.picture;
    if (picture != null) {
      _pass._drawImageAtTile(picture, coord);
      return;
    }
    final hold = _pass._settleHold;
    if (hold != null && hold.containsKey(coord)) {
      _painter._paintTilePixels(
        _pass._canvas,
        (coord: coord, tile: hold[coord]!),
        _pass._layerPaint,
      );
      return;
    }
    final placed = (coord: coord, tile: _painter.surface.tileAt(coord)!);
    if (_pass._pixelFallbackBudget > 0) {
      // First-ever content at this coordinate and not decoded yet: draw
      // per pixel for this frame only — within the budget. Every
      // coordinate here is visible, so the budget spends only where it
      // shows (R27 #2).
      //
      // ⚠️ Spent only where it DREW. The walk is raster order, so a commit
      // whose landing sits below empty rows hands the first four slots to
      // tiles with no ink in them and the picture gets none: measured on a
      // Ctrl+T confirm, all four went to the blank pasteboard row above
      // the artwork and the float contributed zero pixels. A transparent
      // tile costs the same scan either way — it just no longer costs a
      // slot.
      if (_painter._paintTilePixels(_pass._canvas, placed, _pass._layerPaint)) {
        _pass._pixelFallbackBudget -= 1;
      }
    } else {
      // Nothing to draw with: no image, nothing to borrow, no budget left.
      // This branch is the whole stale-tile family's event, and it is
      // invisible because its answer is silence — see
      // [MeasurementMode.showUnpaintedTiles].
      _painter._markUnpainted(_pass._canvas, placed);
    }
  }

  /// A tile's own picture — the cache's (truth or stand-in), or its bytes
  /// uploaded now within this paint's ration where the engine can
  /// ([BitmapTileImageCache.adoptSyncUpload]) — else null.
  ///
  /// The ration is spent on the ANSWER, not the attempt — the same
  /// correction the per-pixel budget needed. On Skia every call declines,
  /// and charging for a decline would be charging for nothing. Where the
  /// engine can, the tile's OWN bytes become its picture right here — no
  /// borrow, no per-pixel path, no waiting a decode round: 30-49 us for a
  /// 256 px tile against 24-103 ms for four tiles of the per-pixel
  /// fallback, and it ADOPTS, so a coordinate pays it once.
  ui.Image? _ownOrUploadedPicture(PlacedTile placed) {
    var image = _painter.tileImageCache.displayImageFor(placed.tile);
    if (image == null && _pass._syncUploadBudget > 0) {
      image = _painter.tileImageCache.adoptSyncUpload(
        placed,
        staleScope: _painter.staleScope,
      );
      if (image != null) {
        _pass._syncUploadBudget -= 1;
      }
    }
    return image;
  }

  /// [placed]'s stand-in composed from its predecessor, put in the cache
  /// and returned — or null when there is no predecessor, its picture is
  /// not on screen, or the composition would exceed what is left of this
  /// paint's budgets (spent on the answer, not the attempt).
  ui.Image? _composeFromPredecessor(
    PlacedTile placed,
    TilePredecessor predecessor,
  ) {
    if (_pass._predecessorTileBudget <= 0 || _pass._predecessorRectBudget <= 0) {
      return null;
    }
    final composed = composePredecessorStandIn(
      cache: _painter.tileImageCache,
      placed: placed,
      predecessor: predecessor,
      rectBudget: _pass._predecessorRectBudget,
    );
    if (composed.image == null) {
      return null;
    }
    _pass._predecessorTileBudget -= 1;
    _pass._predecessorRectBudget -= composed.rects;
    return composed.image;
  }
}
