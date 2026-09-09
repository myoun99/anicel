import '../models/bitmap_tile.dart';
import '../models/brush_pixel_blend_operation.dart';
import '../models/rgba_color.dart';
import '../models/tile_coord.dart';

BitmapTile applyBrushPixelBlendOperationsToBitmapTile({
  required TileCoord coord,
  required BitmapTile tile,
  required Iterable<BrushPixelBlendOperation> operations,
}) {
  final tileGlobalLeft = coord.x * tile.size;
  final tileGlobalTop = coord.y * tile.size;
  final tileGlobalRightExclusive = tileGlobalLeft + tile.size;
  final tileGlobalBottomExclusive = tileGlobalTop + tile.size;

  final updatedPixels = tile.pixels;
  var didApplyOperation = false;

  for (final operation in operations) {
    if (operation.x < tileGlobalLeft ||
        operation.x >= tileGlobalRightExclusive ||
        operation.y < tileGlobalTop ||
        operation.y >= tileGlobalBottomExclusive) {
      continue;
    }

    final localX = operation.x - tileGlobalLeft;
    final localY = operation.y - tileGlobalTop;
    final offset = tile.byteOffsetForPixel(x: localX, y: localY);
    final current = RgbaColor(
      r: updatedPixels[offset],
      g: updatedPixels[offset + 1],
      b: updatedPixels[offset + 2],
      a: updatedPixels[offset + 3],
    );

    if (current != operation.before) {
      throw StateError(
        'BrushPixelBlendOperation before color mismatch at global '
        '(${operation.x}, ${operation.y}), local ($localX, $localY): '
        'expected ${operation.before}, actual $current.',
      );
    }

    updatedPixels[offset] = operation.after.r;
    updatedPixels[offset + 1] = operation.after.g;
    updatedPixels[offset + 2] = operation.after.b;
    updatedPixels[offset + 3] = operation.after.a;
    didApplyOperation = true;
  }

  if (!didApplyOperation) return tile;
  return tile.copyWith(pixels: updatedPixels);
}
