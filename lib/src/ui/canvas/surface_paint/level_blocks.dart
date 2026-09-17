part of '../bitmap_surface_painter.dart';

/// ONE PAINT'S WALK OF THE VISIBLE RECT IN LEVEL BLOCKS (render round 4c,
/// 2026-09-16): above level 0 the surface pass draws each 2^k × 2^k block
/// of coordinates as its level tile ([TilePyramid]) — an exact box mean of
/// what the coordinates show, one tile's worth of pixels, 1:1 in a level
/// buffer's pixels. Every block that shows anything is drawn that way, in
/// the paint that shows it: no block falls back to its coordinates under
/// the caller's scale (the ration that once made some do is the pyramid's
/// 🪦).
///
/// The pyramid's leaf is the pass's one answer to what a coordinate shows
/// ([_CoordinatePicture]): the live stroke's result tile and a committed
/// picture both reach a level tile through it, so no block needs a route
/// of its own.
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
      scope: _painter.lineage,
      keyAt: (TileCoord at) =>
          _pass._coordinates.of(at, withPicture: false)?.key,
      pictureAt: (TileCoord at) =>
          _pass._coordinates.of(at, withPicture: true)?.picture,
    );
    for (final coord in tileCoordsIn(blocks)) {
      final levelTile = TilePyramid.instance.imageFor(
        ask,
        level: _pass._level,
        coord: coord,
      );
      if (levelTile == null) {
        // The block shows nothing.
        continue;
      }
      // 1:1 in the level's pixels: the block is span × span tiles of
      // canvas, and the level tile is one tile's worth of pixels.
      _pass._canvas.save();
      _pass._canvas.scale(span.toDouble());
      _pass._drawImageAtTile(levelTile, coord);
      _pass._canvas.restore();
    }
  }
}
