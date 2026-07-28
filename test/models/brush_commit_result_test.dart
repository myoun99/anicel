import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_commit_result.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('BrushCommitResult', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface({int width = 4, int height = 4, int tileSize = 2}) {
      return BitmapSurface(
        canvasSize: CanvasSize(width: width, height: height),
        tileSize: tileSize,
      );
    }

    DirtyTileSet dirtyTiles([Iterable<TileCoord>? coords]) {
      return DirtyTileSet(coords ?? [TileCoord(x: 0, y: 0)]);
    }

    CacheInvalidationPlan planFor(DirtyTileSet tiles) {
      return CacheInvalidationPlan.fromDirtyTiles(
        layerId: layerId,
        frameId: frameId,
        dirtyTiles: tiles,
      );
    }

    test(
      'noOp(surface:) stores beforeSurface and afterSurface as same surface',
      () {
        final original = surface();
        final result = BrushCommitResult.noOp(surface: original);

        expect(result.beforeSurface, original);
        expect(result.afterSurface, original);
        expect(identical(result.beforeSurface, result.afterSurface), isTrue);
      },
    );

    test('noOp(surface:) has empty DirtyTileSet and CacheInvalidationPlan', () {
      final result = BrushCommitResult.noOp(surface: surface());

      expect(result.dirtyTiles.isEmpty, isTrue);
      expect(result.cacheInvalidationPlan.isEmpty, isTrue);
      expect(result.hasChanges, isFalse);
      expect(result.isNoOp, isTrue);
    });

    test(
      'changed stores surfaces, DirtyTileSet, and CacheInvalidationPlan',
      () {
        final before = surface();
        final after = before.copyWith();
        final tiles = dirtyTiles();
        final plan = planFor(tiles);

        final result = BrushCommitResult.changed(
          beforeSurface: before,
          afterSurface: after,
          dirtyTiles: tiles,
          cacheInvalidationPlan: plan,
        );

        expect(result.beforeSurface, before);
        expect(result.afterSurface, after);
        expect(result.dirtyTiles, tiles);
        expect(result.cacheInvalidationPlan, plan);
        expect(result.hasChanges, isTrue);
      },
    );

    test('changedTileCount equals dirtyTiles.length', () {
      final before = surface();
      final tiles = dirtyTiles([TileCoord(x: 0, y: 0), TileCoord(x: 1, y: 0)]);
      final result = BrushCommitResult.changed(
        beforeSurface: before,
        afterSurface: before.copyWith(),
        dirtyTiles: tiles,
        cacheInvalidationPlan: planFor(tiles),
      );

      expect(result.changedTileCount, tiles.length);
    });

    test('rejects empty dirtyTiles with non-empty cacheInvalidationPlan', () {
      expect(
        () => BrushCommitResult(
          beforeSurface: surface(),
          afterSurface: surface(),
          dirtyTiles: DirtyTileSet.empty(),
          cacheInvalidationPlan: planFor(dirtyTiles()),
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-empty dirtyTiles with empty cacheInvalidationPlan', () {
      expect(
        () => BrushCommitResult(
          beforeSurface: surface(),
          afterSurface: surface(),
          dirtyTiles: dirtyTiles(),
          cacheInvalidationPlan: CacheInvalidationPlan.empty(),
        ),
        throwsArgumentError,
      );
    });

    test('equality and hashCode compare value fields', () {
      final before = surface();
      final after = before.copyWith();
      final tiles = dirtyTiles();
      final a = BrushCommitResult.changed(
        beforeSurface: before,
        afterSurface: after,
        dirtyTiles: tiles,
        cacheInvalidationPlan: planFor(tiles),
      );
      final b = BrushCommitResult.changed(
        beforeSurface: before,
        afterSurface: after,
        dirtyTiles: tiles,
        cacheInvalidationPlan: planFor(tiles),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString describes brush-domain fields without command payload', () {
      final result = BrushCommitResult.noOp(surface: surface());

      expect(result.toString(), contains('BrushCommitResult'));
      expect(result.toString(), contains('dirtyTiles'));
      expect(result.toString(), isNot(contains('TileDeltaCommand')));
    });
  });
}
