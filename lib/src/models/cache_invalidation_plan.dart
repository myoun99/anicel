import '../core/collection_equality.dart';
import '../core/comparing_by_keys.dart';
import 'frame_composite_cache_key.dart';
import 'frame_id.dart';
import 'layer_id.dart';
import 'layer_tile_cache_key.dart';
import 'playback_preview_cache_key.dart';
import 'dirty_tile_set.dart';

class CacheInvalidationPlan {
  CacheInvalidationPlan({
    Iterable<LayerTileCacheKey> layerTiles = const [],
    Iterable<FrameCompositeCacheKey> frameComposites = const [],
    Iterable<PlaybackPreviewCacheKey> playbackPreviews = const [],
  }) : _layerTiles = Set<LayerTileCacheKey>.unmodifiable(layerTiles),
       _frameComposites = Set<FrameCompositeCacheKey>.unmodifiable(
         frameComposites,
       ),
       _playbackPreviews = Set<PlaybackPreviewCacheKey>.unmodifiable(
         playbackPreviews,
       );

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
  final Set<FrameCompositeCacheKey> _frameComposites;
  final Set<PlaybackPreviewCacheKey> _playbackPreviews;

  Set<LayerTileCacheKey> get layerTiles => Set.unmodifiable(_layerTiles);

  Set<FrameCompositeCacheKey> get frameComposites =>
      Set.unmodifiable(_frameComposites);

  Set<PlaybackPreviewCacheKey> get playbackPreviews =>
      Set.unmodifiable(_playbackPreviews);

  bool get isEmpty =>
      _layerTiles.isEmpty &&
      _frameComposites.isEmpty &&
      _playbackPreviews.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get totalKeyCount =>
      _layerTiles.length + _frameComposites.length + _playbackPreviews.length;

  CacheInvalidationPlan addLayerTile(LayerTileCacheKey key) {
    return addLayerTiles([key]);
  }

  CacheInvalidationPlan addFrameComposite(FrameCompositeCacheKey key) {
    return addFrameComposites([key]);
  }

  CacheInvalidationPlan addPlaybackPreview(PlaybackPreviewCacheKey key) {
    return addPlaybackPreviews([key]);
  }

  CacheInvalidationPlan addLayerTiles(Iterable<LayerTileCacheKey> keys) {
    return CacheInvalidationPlan(
      layerTiles: {..._layerTiles, ...keys},
      frameComposites: _frameComposites,
      playbackPreviews: _playbackPreviews,
    );
  }

  CacheInvalidationPlan addFrameComposites(
    Iterable<FrameCompositeCacheKey> keys,
  ) {
    return CacheInvalidationPlan(
      layerTiles: _layerTiles,
      frameComposites: {..._frameComposites, ...keys},
      playbackPreviews: _playbackPreviews,
    );
  }

  CacheInvalidationPlan addPlaybackPreviews(
    Iterable<PlaybackPreviewCacheKey> keys,
  ) {
    return CacheInvalidationPlan(
      layerTiles: _layerTiles,
      frameComposites: _frameComposites,
      playbackPreviews: {..._playbackPreviews, ...keys},
    );
  }

  CacheInvalidationPlan merge(CacheInvalidationPlan other) {
    return CacheInvalidationPlan(
      layerTiles: {..._layerTiles, ...other._layerTiles},
      frameComposites: {..._frameComposites, ...other._frameComposites},
      playbackPreviews: {..._playbackPreviews, ...other._playbackPreviews},
    );
  }

  Map<String, dynamic> toJson() => {
    'layerTiles': _sortedLayerTiles.map((key) => key.toJson()).toList(),
    'frameComposites': _sortedFrameComposites
        .map((key) => key.toJson())
        .toList(),
    'playbackPreviews': _sortedPlaybackPreviews
        .map((key) => key.toJson())
        .toList(),
  };

  factory CacheInvalidationPlan.fromJson(Map<String, dynamic> json) {
    return CacheInvalidationPlan(
      layerTiles: (json['layerTiles'] as List? ?? const []).map(
        (keyJson) =>
            LayerTileCacheKey.fromJson(keyJson as Map<String, dynamic>),
      ),
      frameComposites: (json['frameComposites'] as List? ?? const []).map(
        (keyJson) =>
            FrameCompositeCacheKey.fromJson(keyJson as Map<String, dynamic>),
      ),
      playbackPreviews: (json['playbackPreviews'] as List? ?? const []).map(
        (keyJson) =>
            PlaybackPreviewCacheKey.fromJson(keyJson as Map<String, dynamic>),
      ),
    );
  }

  // The sort exists only so that toJson is deterministic — the plan's own
  // equality is set equality, order-free. Each key order below is the one
  // fact per type; the comparison itself is `comparingByKeys`.
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

  List<FrameCompositeCacheKey> get _sortedFrameComposites {
    return _frameComposites.toList()
      ..sort(comparingByKeys((key) => [key.cutId.value, key.frameIndex]));
  }

  List<PlaybackPreviewCacheKey> get _sortedPlaybackPreviews {
    return _playbackPreviews.toList()..sort(
      comparingByKeys(
        (key) => [
          key.cutId.value,
          key.frameIndex,
          key.previewSize.width,
          key.previewSize.height,
        ],
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheInvalidationPlan &&
          setEquals(other._layerTiles, _layerTiles) &&
          setEquals(other._frameComposites, _frameComposites) &&
          setEquals(other._playbackPreviews, _playbackPreviews);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(_layerTiles),
    Object.hashAllUnordered(_frameComposites),
    Object.hashAllUnordered(_playbackPreviews),
  );

  @override
  String toString() =>
      'CacheInvalidationPlan(layerTiles: $_layerTiles, '
      'frameComposites: $_frameComposites, '
      'playbackPreviews: $_playbackPreviews)';
}
