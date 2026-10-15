import '../models/cache_invalidation_execution_result.dart';
import '../models/brush_frame_cache_invalidation.dart';
import '../models/cache_invalidation_plan.dart';
import '../models/layer_tile_cache_key.dart';

abstract class CacheInvalidationSink {
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation);
  void invalidateLayerTile(LayerTileCacheKey key);
}

CacheInvalidationExecutionResult executeCacheInvalidationPlan({
  required CacheInvalidationPlan plan,
  required CacheInvalidationSink sink,
}) {
  for (final key in plan.layerTiles) {
    sink.invalidateLayerTile(key);
  }

  return CacheInvalidationExecutionResult(
    layerTileCount: plan.layerTiles.length,
  );
}
