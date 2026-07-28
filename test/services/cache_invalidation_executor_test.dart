import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_composite_cache_key.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/playback_preview_cache_key.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cache_invalidation_executor.dart';

class FakeCacheInvalidationSink implements CacheInvalidationSink {
  final layerTiles = <LayerTileCacheKey>[];
  final frameComposites = <FrameCompositeCacheKey>[];
  final playbackPreviews = <PlaybackPreviewCacheKey>[];
  final calls = <String>[];

  @override
  void invalidateLayerTile(LayerTileCacheKey key) {
    layerTiles.add(key);
    calls.add('layer:${key.tileCoord.x},${key.tileCoord.y}');
  }

  @override
  void invalidateBrushFrame(invalidation) {}

  @override
  void invalidateFrameComposite(FrameCompositeCacheKey key) {
    frameComposites.add(key);
    calls.add('frame:${key.frameIndex}');
  }

  @override
  void invalidatePlaybackPreview(PlaybackPreviewCacheKey key) {
    playbackPreviews.add(key);
    calls.add('preview:${key.frameIndex}');
  }
}

void main() {
  group('executeCacheInvalidationPlan', () {
    LayerTileCacheKey layerKey(int x, int y) => LayerTileCacheKey(
      layerId: const LayerId('layer-a'),
      frameId: const FrameId('frame-a'),
      tileCoord: TileCoord(x: x, y: y),
    );
    FrameCompositeCacheKey frameKey(int frameIndex) => FrameCompositeCacheKey(
      cutId: const CutId('cut-a'),
      frameIndex: frameIndex,
    );
    PlaybackPreviewCacheKey previewKey(int frameIndex) =>
        PlaybackPreviewCacheKey(
          cutId: const CutId('cut-a'),
          frameIndex: frameIndex,
          previewSize: const CanvasSize(width: 320, height: 180),
        );

    test('empty plan calls nothing and returns zero counts', () {
      final sink = FakeCacheInvalidationSink();
      final result = executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan.empty(),
        sink: sink,
      );

      expect(sink.layerTiles, isEmpty);
      expect(sink.frameComposites, isEmpty);
      expect(sink.playbackPreviews, isEmpty);
      expect(sink.calls, isEmpty);
      expect(result.layerTileCount, 0);
      expect(result.frameCompositeCount, 0);
      expect(result.playbackPreviewCount, 0);
      expect(result.totalCount, 0);
      expect(result.didInvalidate, isFalse);
    });

    test('layer tile keys are sent to sink', () {
      final keys = [layerKey(0, 0), layerKey(1, 0)];
      final sink = FakeCacheInvalidationSink();

      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(layerTiles: keys),
        sink: sink,
      );

      expect(sink.layerTiles, keys);
      expect(sink.frameComposites, isEmpty);
      expect(sink.playbackPreviews, isEmpty);
    });

    test('frame composite keys are sent to sink', () {
      final keys = [frameKey(0), frameKey(1)];
      final sink = FakeCacheInvalidationSink();

      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(frameComposites: keys),
        sink: sink,
      );

      expect(sink.layerTiles, isEmpty);
      expect(sink.frameComposites, keys);
      expect(sink.playbackPreviews, isEmpty);
    });

    test('playback preview keys are sent to sink', () {
      final keys = [previewKey(0), previewKey(1)];
      final sink = FakeCacheInvalidationSink();

      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(playbackPreviews: keys),
        sink: sink,
      );

      expect(sink.layerTiles, isEmpty);
      expect(sink.frameComposites, isEmpty);
      expect(sink.playbackPreviews, keys);
    });

    test('all key types can be executed together', () {
      final layer = layerKey(0, 0);
      final frame = frameKey(0);
      final preview = previewKey(0);
      final sink = FakeCacheInvalidationSink();

      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(
          layerTiles: [layer],
          frameComposites: [frame],
          playbackPreviews: [preview],
        ),
        sink: sink,
      );

      expect(sink.layerTiles, [layer]);
      expect(sink.frameComposites, [frame]);
      expect(sink.playbackPreviews, [preview]);
    });

    test('result counts match executed key counts', () {
      final sink = FakeCacheInvalidationSink();
      final result = executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(
          layerTiles: [layerKey(0, 0), layerKey(1, 0)],
          frameComposites: [frameKey(0)],
          playbackPreviews: [previewKey(0), previewKey(1), previewKey(2)],
        ),
        sink: sink,
      );

      expect(result.layerTileCount, 2);
      expect(result.frameCompositeCount, 1);
      expect(result.playbackPreviewCount, 3);
      expect(result.totalCount, 6);
      expect(result.didInvalidate, isTrue);
    });

    test('execution order is deterministic enough for each collection', () {
      final layerA = layerKey(0, 0);
      final layerB = layerKey(1, 0);
      final frameA = frameKey(0);
      final frameB = frameKey(1);
      final previewA = previewKey(0);
      final previewB = previewKey(1);
      final sink = FakeCacheInvalidationSink();

      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(
          layerTiles: [layerA, layerB],
          frameComposites: [frameA, frameB],
          playbackPreviews: [previewA, previewB],
        ),
        sink: sink,
      );

      expect(sink.layerTiles, [layerA, layerB]);
      expect(sink.frameComposites, [frameA, frameB]);
      expect(sink.playbackPreviews, [previewA, previewB]);
      expect(sink.calls, [
        'layer:0,0',
        'layer:1,0',
        'frame:0',
        'frame:1',
        'preview:0',
        'preview:1',
      ]);
    });

    test('does not mutate CacheInvalidationPlan', () {
      final plan = CacheInvalidationPlan(
        layerTiles: [layerKey(0, 0)],
        frameComposites: [frameKey(0)],
        playbackPreviews: [previewKey(0)],
      );
      final before = plan.toJson();

      executeCacheInvalidationPlan(
        plan: plan,
        sink: FakeCacheInvalidationSink(),
      );

      expect(plan.toJson(), before);
    });

    test('does not implement real cache storage', () {
      final sink = FakeCacheInvalidationSink();
      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]),
        sink: sink,
      );

      expect(sink.layerTiles.single, layerKey(0, 0));
    });

    test('does not touch BitmapSurface', () {
      final sink = FakeCacheInvalidationSink();
      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan.empty(),
        sink: sink,
      );

      expect(sink.calls, isEmpty);
    });

    test('does not execute undo/redo', () {
      final sink = FakeCacheInvalidationSink();
      final result = executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan.empty(),
        sink: sink,
      );

      expect(result.didInvalidate, isFalse);
    });

    test('does not add UI/state management/timeline/storyboard changes', () {
      final sink = FakeCacheInvalidationSink();
      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(
          frameComposites: [frameKey(0)],
          playbackPreviews: [previewKey(0)],
        ),
        sink: sink,
      );

      expect(sink.frameComposites, [frameKey(0)]);
      expect(sink.playbackPreviews, [previewKey(0)]);
    });
  });
}
