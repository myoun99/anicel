import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_commit_cache_invalidation.dart';

void main() {
  group('cacheInvalidationPlanForDirtyTiles', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    test('returns empty plan for empty DirtyTileSet', () {
      final plan = cacheInvalidationPlanForDirtyTiles(
        layerId: layerId,
        frameId: frameId,
        dirtyTiles: DirtyTileSet.empty(),
      );

      expect(plan.isEmpty, isTrue);
    });

    test('builds LayerTileCacheKey values from DirtyTileSet', () {
      final dirtyTiles = DirtyTileSet([
        TileCoord(x: 0, y: 0),
        TileCoord(x: 1, y: 0),
      ]);
      final plan = cacheInvalidationPlanForDirtyTiles(
        layerId: layerId,
        frameId: frameId,
        dirtyTiles: dirtyTiles,
      );

      expect(
        plan.layerTiles.map((key) => key.tileCoord).toSet(),
        dirtyTiles.coords,
      );
      expect(plan.layerTiles.every((key) => key.layerId == layerId), isTrue);
      expect(plan.layerTiles.every((key) => key.frameId == frameId), isTrue);
    });
  });
}
