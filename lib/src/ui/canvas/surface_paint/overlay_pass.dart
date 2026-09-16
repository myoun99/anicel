part of '../bitmap_surface_painter.dart';

/// ONE PAINT'S OVERLAY: the live stroke's tiles and its stamp, over the
/// committed tiles the base pass drew — a collaborator of
/// `_SurfacePaintPass`, constructed per paint like the pass itself and
/// reaching the paint's state through `_pass` (carved out on 2026-09-16
/// when the level blocks took the pass past the long-class line).
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
    // removes committed pixels exactly like the commit pass will.
    // PROMOTION round: pre-blended tiles carry the COMMIT's finished
    // pixels for their whole coordinate (base included). On the
    // aligned-grid route the base pass SKIPPED those coordinates, so
    // plain srcOver composes them over the paper exactly like the
    // committed tiles will after pen-up; on a mismatched grid the
    // isolation layer is up and the tiles REPLACE (BlendMode.src)
    // instead. The erase/blend paints below serve only overlays that
    // don't pre-blend (the fill stamp, and hosts driving the model
    // directly).
    final overlayPaint = _overlayPaint;
    // R26 #18 (the selection) is NOT clipped here any more: the
    // selection mask rides the pre-blend kernel, so a tile's result
    // already equals the base wherever the selection excludes it. The
    // painter draws the same bytes the commit will hold — which is
    // also what lets a selected stroke keep the whole-coordinate
    // replacement path below instead of an isolation layer.
    final overlayTileSize = _overlay.tileSize.toDouble();
    for (final entry in _overlay.tileImages.entries) {
      if (_pass._committedWins?.contains(entry.key) ?? false) {
        // The base pass already drew this coordinate's finished tile.
        continue;
      }
      final origin = Offset(
        entry.key.x * overlayTileSize,
        entry.key.y * overlayTileSize,
      );
      if (!_tileIsVisible(origin, overlayTileSize)) {
        continue;
      }
      _pass._canvas.drawImage(entry.value, origin, overlayPaint);
    }
    // R23: a fill tap's overlay is ONE pre-decoded stamp image at the
    // commit's exact placement (never coexists with stroke tiles).
    final stampImage = _overlay.stampImage;
    if (stampImage != null) {
      _pass._canvas.drawImage(stampImage, _overlay.stampOffset, overlayPaint);
    }
  }

  /// 🚨★★★**THE SAME VISIBLE-RECT LAW THE BASE PASS KEEPS**
  /// (`tilesUnderRect` at `_SurfacePaintPass._paintVisibleTiles`), and the
  /// overlay pass was the one place it was not applied. Overlay tiles
  /// ACCUMULATE for the whole life of a stroke — nothing leaves the map
  /// until pen-up — so by the third dab that map is the bounding box of
  /// the WHOLE stroke, and a long line paid its full length in draws on
  /// every frame of every dab, off-screen coordinates included.
  bool _tileIsVisible(Offset origin, double tileSize) =>
      _pass._visibleRect.overlaps(
        Rect.fromLTWH(origin.dx, origin.dy, tileSize, tileSize),
      );
}
