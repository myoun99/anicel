import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/tile_coord.dart';

/// The straight RGBA of [surface] at ([x], [y]), read where its tile holds
/// it, or null beyond the pasteboard wall: what a test asks of a picture it
/// made, at any tile side. The eyedropper's own road is `surfacePixelRgba`.
// ⏳Till a tile's bytes are the engine's alone (flip lane ⓔ).
int? surfaceRgbaInPlace(BitmapSurface surface, int x, int y) {
  if (!surface.pasteboard.containsPixel(x: x, y: y)) {
    return null;
  }
  final tileSize = surface.tileSize;
  final tile = surface.tileAt(
    TileCoord(x: floorDiv(x, tileSize), y: floorDiv(y, tileSize)),
  );
  if (tile == null) {
    return 0;
  }
  final index = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
  return tile.readPixels(
    (_, pixels) =>
        (pixels[index] << 24) |
        (pixels[index + 1] << 16) |
        (pixels[index + 2] << 8) |
        pixels[index + 3],
  );
}
