import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_commit_result.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_commit_result_apply.dart';

void main() {
  group('applyBrushCommitResultToBitmapSurface', () {
    BitmapSurface surface({bool withTile = false}) {
      final coord = TileCoord(x: 0, y: 0);
      return BitmapSurface(
        canvasSize: CanvasSize(width: 4, height: 4),
        tileSize: 2,
        tiles: withTile
            ? {coord: BitmapTile.blank(coord: coord, size: 2)}
            : const {},
      );
    }

    BrushCommitResult changed(BitmapSurface before, BitmapSurface after) {
      final dirtyTiles = DirtyTileSet([TileCoord(x: 0, y: 0)]);
      return BrushCommitResult.changed(
        beforeSurface: before,
        afterSurface: after,
        dirtyTiles: dirtyTiles,
        cacheInvalidationPlan: CacheInvalidationPlan.fromDirtyTiles(
          layerId: const LayerId('layer-a'),
          frameId: const FrameId('frame-a'),
          dirtyTiles: dirtyTiles,
        ),
      );
    }

    test('apply no-op returns the input surface', () {
      final original = surface();
      final result = applyBrushCommitResultToBitmapSurface(
        surface: original,
        result: BrushCommitResult.noOp(surface: original),
      );

      expect(result, original);
    });

    test('apply changed result requires input surface == beforeSurface', () {
      final before = surface();
      final after = surface(withTile: true);
      expect(
        () => applyBrushCommitResultToBitmapSurface(
          surface: surface(withTile: true),
          result: changed(before, after),
        ),
        throwsArgumentError,
      );
    });

    test('apply changed result returns afterSurface', () {
      final before = surface();
      final after = surface(withTile: true);
      final result = applyBrushCommitResultToBitmapSurface(
        surface: before,
        result: changed(before, after),
      );

      expect(result, after);
    });
  });
}
