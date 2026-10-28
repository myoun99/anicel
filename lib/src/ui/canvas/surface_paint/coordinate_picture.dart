part of '../bitmap_surface_painter.dart';

/// 🚨★★★THE ONE LAW OF WHAT A COORDINATE SHOWS (유저 절대규칙 2026-09-17:
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」). Every coordinate of the
/// surface shows ONE picture right now, decided here and nowhere else, and
/// every paint draws it — at 100%, and reduced by the GPU from that same
/// picture's chain ([BitmapTileImageCache.chainedPictureFor]) — so the
/// screen shows the same bytes at every zoom and at every moment of a
/// stroke, and nothing that draws a coordinate gets to decide differently.
/// ↩️Below 100% a block of coordinates was drawn as one level tile made
/// from their pictures, until one-picture-per-frame ②-5b-2.
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
/// 🚨★★★MADE IN THE PAINT THAT SHOWS IT — EVERY ONE IT SHOWS, a chain
/// included. 🪦A ration once stood on the level tiles (render round 4c,
/// 2026-09-16 → 09-17: 32 a paint): nothing asks a painter to paint again,
/// so the blocks past it stayed sampled another way beside their neighbours
/// until something else repainted — measured, 180 of 1080 sampled pixels a
/// second later. A paint makes everything it shows.
///
/// 🚨A collaborator of `_SurfacePaintPass`, one per paint like the pass
/// itself.
class _CoordinatePicture {
  _CoordinatePicture(this._pass);

  final _SurfacePaintPass _pass;

  BitmapSurfacePainter get _painter => _pass._painter;

  /// Draws the picture [coord] shows — carrying its chain where this paint
  /// draws it reduced — if it shows anything.
  void paint(TileCoord coord) {
    final reduced = _pass._reduced;
    final overlay = _pass._overlay;
    if (overlay != null &&
        _pass._overlayReplacesCoords &&
        overlay.tileImages.containsKey(coord)) {
      // The overlay tile holds the commit's own bytes exactly — the
      // picture pen-up hands to the committed tile — so it is the final
      // picture already.
      final image = reduced
          ? overlay.chainedTileImageAt(coord)
          : overlay.tileImages[coord];
      if (image != null) {
        _pass._drawImageAtTile(image, coord);
      }
      return;
    }
    final tile = _painter.surface.tileAt(coord);
    if (tile == null) {
      return;
    }
    final pictures = _painter.tileImageCache;
    if (reduced) {
      _pass._drawImageAtTile(pictures.chainedPictureFor(tile), coord);
    } else {
      _pass._drawPictureAtTile(pictures.pictureFor(tile), coord);
    }
  }
}
