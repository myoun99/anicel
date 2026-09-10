import '../../models/brush_frame_cache_invalidation.dart';
import '../../models/cache_invalidation_execution_result.dart';
import '../../models/frame_composite_cache_key.dart';
import '../../models/layer_tile_cache_key.dart';
import '../../models/playback_preview_cache_key.dart';
import '../../services/cache_invalidation_executor.dart';
import '../canvas/tile_predecessors.dart';

/// Debug/manual cache invalidation recorder for standalone Brush hosts
/// (the timesheet ink stack and the smoke screens run without the editor
/// session's hub).
///
/// The recording is BOUNDED: the hosts using this sink live for the whole
/// session, and an unbounded per-stroke key log is exactly the kind of
/// silent accumulation the brush stack must never carry. The newest keys
/// win; [latestResult] and single-stroke assertions are unaffected.
class BrushEditCacheInvalidationSink implements CacheInvalidationSink {
  /// Generous per-list cap — far above any single stroke's key count.
  static const int maxRecordedKeys = 4096;

  final layerTiles = <LayerTileCacheKey>[];
  final frameComposites = <FrameCompositeCacheKey>[];
  final playbackPreviews = <PlaybackPreviewCacheKey>[];
  final brushFrames = <BrushFrameCacheInvalidation>[];

  CacheInvalidationExecutionResult get latestResult =>
      CacheInvalidationExecutionResult(
        layerTileCount: layerTiles.length,
        frameCompositeCount: frameComposites.length,
        playbackPreviewCount: playbackPreviews.length,
      );

  void _record<T>(List<T> list, T value) {
    list.add(value);
    if (list.length > maxRecordedKeys) {
      list.removeRange(0, list.length - maxRecordedKeys);
    }
  }

  @override
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation) {
    // The standalone hosts draw through the same painter as the editor, so
    // their tiles need the same truthful first frame (F-68 root fix).
    notePredecessorsFromInvalidation(invalidation);
    _record(brushFrames, invalidation);
  }

  @override
  void invalidateFrameComposite(FrameCompositeCacheKey key) =>
      _record(frameComposites, key);

  @override
  void invalidateLayerTile(LayerTileCacheKey key) => _record(layerTiles, key);

  @override
  void invalidatePlaybackPreview(PlaybackPreviewCacheKey key) =>
      _record(playbackPreviews, key);
}
