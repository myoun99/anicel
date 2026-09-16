part of '../bitmap_surface_painter.dart';

/// ONE PAINT'S WALK OF THE VISIBLE RECT IN LEVEL BLOCKS (render round 4c,
/// 2026-09-16): above level 0 the surface pass draws each 2^k × 2^k block
/// of coordinates as its level tile ([TilePyramid]) — an exact box mean of
/// what the coordinates show, one tile's worth of pixels, 1:1 in a level
/// buffer's pixels — and only a block no level tile can be made for yet
/// falls back to its coordinates under the caller's scale, drawn exactly
/// as level 0 draws them.
///
/// The pyramid's leaf is the pass's one answer to what a coordinate shows
/// (`_SurfacePaintPass._coordinate`): the live stroke, a held tile, a
/// stand-in and a committed picture all reach a level tile through it, so
/// no block needs a route of its own.
///
/// 🚨A collaborator of `_SurfacePaintPass`, constructed per paint like the
/// pass itself; it reaches the paint's state through `_pass`.
class _LevelBlocks {
  _LevelBlocks(this._pass);

  final _SurfacePaintPass _pass;

  BitmapSurfacePainter get _painter => _pass._painter;

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
      tileSize: surface.tileSize,
      scope: _painter.staleScope,
      keyAt: (TileCoord at) =>
          _pass._coordinates.of(at, withPicture: false)?.key,
      pictureAt: (TileCoord at) =>
          _pass._coordinates.of(at, withPicture: true)?.picture,
      mayMake: _mayMake,
    );
    for (final coord in tileCoordsIn(blocks)) {
      final levelTile = TilePyramid.instance.imageFor(
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
        }
        _pass._coordinates.paint(at);
      }
    }
  }

  /// The paint's ration of level tiles, each a `toImageSync` of four
  /// pictures — rationed like the sync uploads, for the same reason: a
  /// cold zoomed-out view is the whole visible grid at once, and the
  /// blocks that miss out draw their coordinates this frame and ask again
  /// on the next. The same number ([BitmapSurfacePainter.decodeStartBudget])
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
}
