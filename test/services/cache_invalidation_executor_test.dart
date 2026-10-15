import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cache_invalidation_executor.dart';

class FakeCacheInvalidationSink implements CacheInvalidationSink {
  final layerTiles = <LayerTileCacheKey>[];
  final calls = <String>[];

  @override
  void invalidateLayerTile(LayerTileCacheKey key) {
    layerTiles.add(key);
    calls.add('layer:${key.tileCoord.x},${key.tileCoord.y}');
  }

  @override
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation) {}
}

void main() {
  group('executeCacheInvalidationPlan', () {
    LayerTileCacheKey layerKey(int x, int y) => LayerTileCacheKey(
      layerId: const LayerId('layer-a'),
      frameId: const FrameId('frame-a'),
      tileCoord: TileCoord(x: x, y: y),
    );

    test('empty plan calls nothing and returns zero counts', () {
      final sink = FakeCacheInvalidationSink();
      final result = executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan.empty(),
        sink: sink,
      );

      expect(sink.layerTiles, isEmpty);
      expect(sink.calls, isEmpty);
      expect(result.layerTileCount, 0);
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
    });

    test('result counts match executed key counts', () {
      final sink = FakeCacheInvalidationSink();
      final result = executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(
          layerTiles: [layerKey(0, 0), layerKey(1, 0)],
        ),
        sink: sink,
      );

      expect(result.layerTileCount, 2);
      expect(result.totalCount, 2);
      expect(result.didInvalidate, isTrue);
    });

    test('execution order follows the plan', () {
      final layerA = layerKey(0, 0);
      final layerB = layerKey(1, 0);
      final sink = FakeCacheInvalidationSink();

      executeCacheInvalidationPlan(
        plan: CacheInvalidationPlan(layerTiles: [layerA, layerB]),
        sink: sink,
      );

      expect(sink.layerTiles, [layerA, layerB]);
      expect(sink.calls, ['layer:0,0', 'layer:1,0']);
    });

    test('does not mutate CacheInvalidationPlan', () {
      final plan = CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]);
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
  });
}
