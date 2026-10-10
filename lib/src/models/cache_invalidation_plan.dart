import '../core/collection_equality.dart';
import '../core/comparing_by_keys.dart';
import 'frame_id.dart';
import 'layer_id.dart';
import 'layer_tile_cache_key.dart';
import 'dirty_tile_set.dart';

/// The caches a change leaves stale, by key.
///
/// ↩️It had two more kinds — a cut frame's composite and a playback
/// preview — from the day it was drawn up, and nothing ever made a plan
/// with either or acted on one: the composites validated themselves by
/// signature, and no preview cache was built. They went with the composite
/// cache (2026-10-10, when the whole film came to be drawn from the
/// canvas's own pictures).
class CacheInvalidationPlan {
  CacheInvalidationPlan({Iterable<LayerTileCacheKey> layerTiles = const []})
    : _layerTiles = Set<LayerTileCacheKey>.unmodifiable(layerTiles);

  factory CacheInvalidationPlan.empty() => CacheInvalidationPlan();

  factory CacheInvalidationPlan.fromDirtyTiles({
    required LayerId layerId,
    required FrameId frameId,
    required DirtyTileSet dirtyTiles,
  }) {
    return CacheInvalidationPlan(
      layerTiles: dirtyTiles.coords.map(
        (tileCoord) => LayerTileCacheKey(
          layerId: layerId,
          frameId: frameId,
          tileCoord: tileCoord,
        ),
      ),
    );
  }

  final Set<LayerTileCacheKey> _layerTiles;

  Set<LayerTileCacheKey> get layerTiles => Set.unmodifiable(_layerTiles);

  bool get isEmpty => _layerTiles.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get totalKeyCount => _layerTiles.length;

  CacheInvalidationPlan addLayerTile(LayerTileCacheKey key) {
    return addLayerTiles([key]);
  }

  CacheInvalidationPlan addLayerTiles(Iterable<LayerTileCacheKey> keys) {
    return CacheInvalidationPlan(layerTiles: {..._layerTiles, ...keys});
  }

  CacheInvalidationPlan merge(CacheInvalidationPlan other) {
    return CacheInvalidationPlan(
      layerTiles: {..._layerTiles, ...other._layerTiles},
    );
  }

  Map<String, dynamic> toJson() => {
    'layerTiles': _sortedLayerTiles.map((key) => key.toJson()).toList(),
  };

  factory CacheInvalidationPlan.fromJson(Map<String, dynamic> json) {
    return CacheInvalidationPlan(
      layerTiles: (json['layerTiles'] as List? ?? const []).map(
        (keyJson) =>
            LayerTileCacheKey.fromJson(keyJson as Map<String, dynamic>),
      ),
    );
  }

  // The sort exists only so that toJson is deterministic — the plan's own
  // equality is set equality, order-free. The comparison itself is
  // `comparingByKeys`.
  List<LayerTileCacheKey> get _sortedLayerTiles {
    return _layerTiles.toList()..sort(
      comparingByKeys(
        (key) => [
          key.layerId.value,
          key.frameId.value,
          key.tileCoord.y,
          key.tileCoord.x,
        ],
      ),
    );
  }


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheInvalidationPlan &&
          setEquals(other._layerTiles, _layerTiles);

  @override
  int get hashCode => Object.hashAllUnordered(_layerTiles);

  @override
  String toString() => 'CacheInvalidationPlan(layerTiles: $_layerTiles)';
}
