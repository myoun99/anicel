part of '../bitmap_surface_painter.dart';

/// 🚨★★★THE ONE LAW OF WHAT A COORDINATE SHOWS (유저 절대규칙 2026-09-17:
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」). Every coordinate of the
/// surface shows ONE picture right now, decided here and nowhere else:
/// level 0 draws it ([paint]) and every level above is made from it
/// ([TilePyramid], through [_LevelBlocks]), so the screen shows the same
/// bytes at every zoom and at every moment of a stroke — and nothing that
/// draws a coordinate gets to decide differently.
///
/// The answer has two clauses and no third: the live stroke's result tile
/// where the overlay replaces the coordinate (it already holds the
/// committed pixels blended with the stroke), else the committed tile's
/// OWN picture — the one it has, or the one made now from its own bytes
/// through the one door ([BitmapTileImageCache.pictureFor]). A coordinate
/// with bytes never shows anything but a picture of those bytes: not the
/// previous tile's picture, not a composition, not a per-pixel frame, not
/// a blank — every one of those was a way of waiting for a decode, and
/// nothing waits any more.
///
/// 🚨A collaborator of `_SurfacePaintPass`, one per paint like the pass
/// itself.
class _CoordinatePicture {
  _CoordinatePicture(this._pass);

  final _SurfacePaintPass _pass;

  BitmapSurfacePainter get _painter => _pass._painter;

  /// What [coord] shows. `key` is what the answer is made from — the tile
  /// object when the picture is that tile's own (a truth key survives its
  /// picture's eviction: the tile is pictured again, the same bytes), the
  /// overlay's picture object when the overlay stands at the coordinate —
  /// and it is what a level tile is keyed by. `picture` is that picture,
  /// or null only when [withPicture] is false; the whole answer is null
  /// when the coordinate shows nothing.
  ///
  /// [withPicture] false asks only for the key — which is all a kept level
  /// tile needs to know it still stands, and asking for it must not make
  /// a picture nobody draws.
  ({Object key, ui.Image? picture})? of(
    TileCoord coord, {
    required bool withPicture,
  }) {
    final overlay = _pass._overlay;
    final overlayImage = overlay != null && _pass._overlayReplacesCoords
        ? overlay.tileImages[coord]
        : null;
    if (overlayImage != null) {
      // The overlay tile holds the commit's own bytes exactly — the
      // picture pen-up hands to the committed tile — so it is the final
      // picture already.
      return (key: overlayImage, picture: overlayImage);
    }
    final tile = _painter.surface.tileAt(coord);
    if (tile == null) {
      return null;
    }
    return (
      key: tile,
      picture: withPicture
          ? _painter.tileImageCache.pictureFor(tile)
          : null,
    );
  }

  /// Draws what [coord] shows ([of]) at level 0.
  void paint(TileCoord coord) {
    final now = of(coord, withPicture: true);
    if (now == null) {
      return;
    }
    _pass._drawImageAtTile(now.picture!, coord);
  }
}
