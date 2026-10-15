import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';

void main() {
  group('CacheInvalidationPlan', () {
    LayerTileCacheKey layerKey(
      int x,
      int y, {
      String layer = 'layer-a',
      String frame = 'frame-a',
    }) => LayerTileCacheKey(
      layerId: LayerId(layer),
      frameId: FrameId(frame),
      tileCoord: TileCoord(x: x, y: y),
    );

    test('empty plan is empty', () {
      final plan = CacheInvalidationPlan.empty();
      expect(plan.isEmpty, isTrue);
      expect(plan.totalKeyCount, 0);
    });

    test('constructor stores layer tile keys', () {
      final key = layerKey(0, 0);
      expect(
        CacheInvalidationPlan(layerTiles: [key]).layerTiles,
        contains(key),
      );
    });

    test('constructor defensively copies input iterables', () {
      final keys = [layerKey(0, 0)];
      final plan = CacheInvalidationPlan(layerTiles: keys);
      keys.add(layerKey(1, 0));
      expect(plan.layerTiles.length, 1);
    });

    test('exposed key set is unmodifiable', () {
      expect(
        () => CacheInvalidationPlan.empty().layerTiles.add(layerKey(0, 0)),
        throwsUnsupportedError,
      );
    });

    test('isEmpty is true only when no layer tile is named', () {
      expect(CacheInvalidationPlan.empty().isEmpty, isTrue);
      expect(
        CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]).isEmpty,
        isFalse,
      );
    });

    test('isNotEmpty is true when a layer tile is named', () {
      expect(CacheInvalidationPlan.empty().isNotEmpty, isFalse);
      expect(
        CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]).isNotEmpty,
        isTrue,
      );
    });

    test('totalKeyCount counts the layer tiles', () {
      expect(
        CacheInvalidationPlan(
          layerTiles: [layerKey(0, 0), layerKey(1, 0)],
        ).totalKeyCount,
        2,
      );
    });

    test('addLayerTile returns new plan', () {
      final original = CacheInvalidationPlan.empty();
      final next = original.addLayerTile(layerKey(0, 0));
      expect(next.layerTiles.length, 1);
      expect(original.layerTiles, isEmpty);
    });

    test('addLayerTiles does not mutate the original', () {
      final original = CacheInvalidationPlan.empty();
      original.addLayerTiles([layerKey(0, 0)]);
      expect(original.isEmpty, isTrue);
    });

    test('addLayerTiles collapses duplicates', () {
      final key = layerKey(0, 0);
      expect(
        CacheInvalidationPlan.empty()
            .addLayerTiles([key, key])
            .layerTiles
            .length,
        1,
      );
    });

    test('merge combines the layer tiles', () {
      final merged = CacheInvalidationPlan(
        layerTiles: [layerKey(0, 0)],
      ).merge(CacheInvalidationPlan(layerTiles: [layerKey(1, 0)]));
      expect(merged.totalKeyCount, 2);
    });

    test('merge does not mutate originals', () {
      final a = CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]);
      final b = CacheInvalidationPlan(layerTiles: [layerKey(1, 0)]);
      a.merge(b);
      expect(a.totalKeyCount, 1);
      expect(b.totalKeyCount, 1);
    });

    test(
      'fromDirtyTiles creates LayerTileCacheKey entries for every dirty tile',
      () {
        final dirtyTiles = DirtyTileSet([
          TileCoord(x: 0, y: 0),
          TileCoord(x: 1, y: 0),
        ]);
        final plan = CacheInvalidationPlan.fromDirtyTiles(
          layerId: const LayerId('layer-a'),
          frameId: const FrameId('frame-a'),
          dirtyTiles: dirtyTiles,
        );
        expect(plan.layerTiles, containsAll([layerKey(0, 0), layerKey(1, 0)]));
      },
    );

    test('equality ignores insertion order', () {
      final a = layerKey(0, 0);
      final b = layerKey(1, 0);
      expect(
        CacheInvalidationPlan(layerTiles: [a, b]),
        CacheInvalidationPlan(layerTiles: [b, a]),
      );
    });

    test('hashCode ignores insertion order', () {
      final a = layerKey(0, 0);
      final b = layerKey(1, 0);
      expect(
        CacheInvalidationPlan(layerTiles: [a, b]).hashCode,
        CacheInvalidationPlan(layerTiles: [b, a]).hashCode,
      );
    });

    test('toJson/fromJson round-trips', () {
      final plan = CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]);
      expectJsonRoundTrip(plan, CacheInvalidationPlan.fromJson);
    });

    test('toJson emits deterministic order', () {
      final plan = CacheInvalidationPlan(
        layerTiles: [
          layerKey(2, 0),
          layerKey(0, 1),
          layerKey(1, 0, layer: 'layer-b'),
          layerKey(1, 0),
        ],
      );
      final json = plan.toJson();
      expect(
        (json['layerTiles'] as List).map(
          (e) => ((e as Map)['tileCoord'] as Map)['x'],
        ),
        [1, 2, 0, 1],
      );
    });
  });
}
