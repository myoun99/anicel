import '../models/bitmap_tile.dart';
import '../models/brush_pixel_blend_operation.dart';
import '../models/tile_coord.dart';
import 'bitmap_tile_operation_apply.dart';

BitmapTile? materializedBitmapTileForOperations({
  required TileCoord coord,
  required BitmapTile tile,
  required Iterable<BrushPixelBlendOperation> operations,
}) {
  final updatedTile = applyBrushPixelBlendOperationsToBitmapTile(
    coord: coord,
    tile: tile,
    operations: operations,
  );

  if (updatedTile == tile) return null;
  return updatedTile;
}
