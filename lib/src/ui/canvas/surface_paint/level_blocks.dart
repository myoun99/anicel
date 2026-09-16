part of '../bitmap_surface_painter.dart';

/// ONE PAINT'S WALK OF THE VISIBLE RECT IN LEVEL BLOCKS (render round 4c,
/// 2026-09-16): above level 0 the surface pass draws each 2^k × 2^k block
/// of tiles as its level tile ([TilePyramid]) — an exact box mean of the
/// block, one tile's worth of pixels, 1:1 in a level buffer's pixels —
/// and only a block no level tile can be made for yet, or that a live
/// draw touches, falls back to its tiles under the caller's scale, exactly
/// as level 0 draws them.
///
/// 🚨A collaborator of `_SurfacePaintPass`, constructed per paint like the
/// pass itself; it reaches the paint's state through `_pass`.
class _LevelBlocks {
  _LevelBlocks(this._pass);

  final _SurfacePaintPass _pass;

  BitmapSurfacePainter get _painter => _pass._painter;

  /// ⛔A block the LIVE overlay or the settle hold touches keeps the tile
  /// route: the overlay's result tile replaces its coordinate outright and
  /// the hold pins the pre-stroke tile, and a level tile under either
  /// would put the committed picture back beneath them — the double-
  /// density ghost, one level down.
  void paint() {
    final surface = _painter.surface;
    final span = 1 << _pass._level;
    final visible = _pass._visibleRect;
    if (visible.isEmpty) {
      return;
    }
    // The blocks are a tile grid of their own — span tiles a side — so the
    // one "which tiles does this rect touch" law walks them.
    final blocks = tileRangeCovering(
      left: visible.left,
      top: visible.top,
      right: visible.right,
      bottom: visible.bottom,
      tileSize: surface.tileSize * span,
    );
    final ask = (
      surface: surface,
      scope: _painter.staleScope,
      cache: _painter.tileImageCache,
      // A tile's own picture, or one uploaded now within the paint's
      // ration; null makes the block draw its tiles.
      picture: _pass._ownOrUploadedPicture,
      mayMake: _mayMake,
    );
    for (final coord in tileCoordsIn(blocks)) {
      final levelTile = _liveDrawTouches(coord)
          ? null
          : TilePyramid.instance.imageFor(
              ask,
              level: _pass._level,
              coord: coord,
            );
      if (levelTile != null) {
        // 1:1 in the level's pixels: the block is span × span tiles of
        // canvas, and the level tile is one tile's worth of pixels.
        _pass._canvas.save();
        _pass._canvas.scale(span.toDouble());
        _pass._drawImageAtTile(levelTile, coord);
        _pass._canvas.restore();
        continue;
      }
      for (final at in TilePyramid.tilesOfBlock(_pass._level, coord)) {
        final tile = surface.tileAt(at);
        if (tile != null) {
          _painter.pictureBudget.shown(_painter.staleScope, tile);
          _pass._paintTile((coord: at, tile: tile));
        }
      }
    }
  }

  /// The paint's ration of level tiles, each a `toImageSync` of four
  /// pictures — rationed like the sync uploads, for the same reason: a
  /// cold zoomed-out view is the whole visible grid at once, and the
  /// blocks that miss out draw their tiles this frame and ask again on
  /// the next. The same number ([BitmapSurfacePainter.decodeStartBudget])
  /// because it is the same shape of cost being spread over frames; the
  /// seam probe measured a make at tens of microseconds, so one paint's
  /// ration is under two milliseconds.
  bool _mayMake() {
    if (_pass._levelTileBudget <= 0) {
      return false;
    }
    _pass._levelTileBudget -= 1;
    return true;
  }

  bool _liveDrawTouches(TileCoord blockCoord) {
    final overlay = _pass._overlayReplacesCoords ? _pass._overlay : null;
    final hold = _pass._settleHold;
    if (overlay == null && hold == null) {
      return false;
    }
    return TilePyramid.tilesOfBlock(_pass._level, blockCoord).any(
      (at) =>
          (overlay?.tileImages.containsKey(at) ?? false) ||
          (hold?.containsKey(at) ?? false),
    );
  }
}
