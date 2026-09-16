part of '../bitmap_surface_painter.dart';

/// ONE PAINT'S OVERLAY: the live stroke's tiles where they are an
/// OPERATION on the committed pixels rather than a picture of the
/// coordinate — over what the base pass drew. A collaborator of
/// `_SurfacePaintPass`, constructed per paint like the pass itself and
/// reaching the paint's state through `_pass` (carved out on 2026-09-16
/// when the level blocks took the pass past the long-class line).
///
/// ⛔A PRE-BLENDED overlay on the surface's own grid is not drawn here at
/// all: its tiles REPLACE their coordinates, so they are those coordinates'
/// pictures and the base pass draws them as such at every level
/// (`_SurfacePaintPass._coordinate`, the one law of what a coordinate
/// shows). Two draws of one coordinate is the double-density ghost.
class _OverlayPass {
  _OverlayPass(this._pass, this._overlay);

  final _SurfacePaintPass _pass;
  final ActiveStrokeOverlayModel _overlay;

  Paint get _overlayPaint => _pass._livePreviewPaint(
    blendMode: _overlay.blendMode,
    erase: _overlay.erase,
    preBlended: _overlay.preBlended,
    replacesCoords: _pass._overlayReplacesCoords,
  );

  void paint() {
    // The live stroke renders through the EXACT pipeline the committed
    // tiles use — premultiplied bytes decoded to images, drawn with
    // nearest sampling — so live and committed pixels rasterize
    // identically at any zoom (one code path; rect-geometry replay
    // diverged from image sampling at fractional zoom). Overlay tiles
    // never overlap, so plain source-over per tile is exact. An ERASE
    // stroke draws destination-out instead: the accumulated stroke alpha
    // removes committed pixels exactly like the commit pass will. On a
    // mismatched grid the isolation layer is up and pre-blended tiles
    // REPLACE (BlendMode.src) instead. The erase/blend paints serve only
    // overlays that don't pre-blend (hosts driving the model directly).
    if (_pass._overlayReplacesCoords) {
      return;
    }
    final overlayPaint = _overlayPaint;
    // R26 #18 (the selection) is NOT clipped here any more: the
    // selection mask rides the pre-blend kernel, so a tile's result
    // already equals the base wherever the selection excludes it.
    final overlayTileSize = _overlay.tileSize.toDouble();
    for (final entry in _overlay.tileImages.entries) {
      final origin = Offset(
        entry.key.x * overlayTileSize,
        entry.key.y * overlayTileSize,
      );
      if (!_pass._visibleRect.overlaps(
        Rect.fromLTWH(origin.dx, origin.dy, overlayTileSize, overlayTileSize),
      )) {
        continue;
      }
      _pass._canvas.drawImage(entry.value, origin, overlayPaint);
    }
  }
}
