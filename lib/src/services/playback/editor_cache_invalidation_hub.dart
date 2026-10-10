import '../../models/brush_frame_cache_invalidation.dart';
import '../../models/layer_tile_cache_key.dart';
import '../cache_invalidation_executor.dart';

/// The production [CacheInvalidationSink]: fans invalidation events out to
/// registered listeners (playback caches, prerender scheduler).
///
/// This is the first real consumer of the events the brush editing
/// coordinator has been emitting on commit/undo/redo. Listeners use them for
/// early eviction and prerender re-queuing; cache CORRECTNESS never depends
/// on them (a layer image validates itself by its cel's revision).
class EditorCacheInvalidationHub implements CacheInvalidationSink {
  final List<void Function(BrushFrameCacheInvalidation)> _brushFrameListeners =
      [];

  void addBrushFrameListener(
    void Function(BrushFrameCacheInvalidation) listener,
  ) {
    _brushFrameListeners.add(listener);
  }

  void removeBrushFrameListener(
    void Function(BrushFrameCacheInvalidation) listener,
  ) {
    _brushFrameListeners.remove(listener);
  }

  @override
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation) {
    for (final listener in List.of(_brushFrameListeners)) {
      listener(invalidation);
    }
  }

  // A brush commit names its layer tiles, and no cache here is keyed by
  // tile: the layer images are invalidated by the brush frame above.
  @override
  void invalidateLayerTile(LayerTileCacheKey key) {}
}
