import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_commit_result.dart';
import 'package:anicel/src/models/brush_surface_edit.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('BrushSurfaceEdit', () {
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

    BrushCommitResult changedResult(BitmapSurface before, BitmapSurface after) {
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

    test('no-op edit requires equal before/after surfaces', () {
      final before = surface();
      final after = surface(withTile: true);

      expect(
        () => BrushSurfaceEdit(
          beforeSurface: before,
          afterSurface: after,
          commitResult: BrushCommitResult.noOp(surface: before),
        ),
        throwsArgumentError,
      );
    });

    test('no-op edit stores equal before/after/commitResult', () {
      final original = surface();
      final result = BrushCommitResult.noOp(surface: original);
      final edit = BrushSurfaceEdit(
        beforeSurface: original,
        afterSurface: original,
        commitResult: result,
      );

      expect(edit.beforeSurface, original);
      expect(edit.afterSurface, original);
      expect(edit.commitResult, result);
      expect(edit.isNoOp, isTrue);
    });

    test('changed edit stores before/after/commitResult', () {
      final before = surface();
      final after = surface(withTile: true);
      final result = changedResult(before, after);
      final edit = BrushSurfaceEdit(
        beforeSurface: before,
        afterSurface: after,
        commitResult: result,
      );

      expect(edit.beforeSurface, before);
      expect(edit.afterSurface, after);
      expect(edit.commitResult, result);
      expect(edit.hasChanges, isTrue);
      expect(edit.effectiveSurface, after);
    });
  });
}
