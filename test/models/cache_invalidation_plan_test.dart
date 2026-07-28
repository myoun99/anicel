import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_composite_cache_key.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/playback_preview_cache_key.dart';
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
    FrameCompositeCacheKey frameKey(int frameIndex, {String cut = 'cut-a'}) =>
        FrameCompositeCacheKey(cutId: CutId(cut), frameIndex: frameIndex);
    PlaybackPreviewCacheKey previewKey(
      int frameIndex,
      int width,
      int height, {
      String cut = 'cut-a',
    }) => PlaybackPreviewCacheKey(
      cutId: CutId(cut),
      frameIndex: frameIndex,
      previewSize: CanvasSize(width: width, height: height),
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

    test('constructor stores frame composite keys', () {
      final key = frameKey(0);
      expect(
        CacheInvalidationPlan(frameComposites: [key]).frameComposites,
        contains(key),
      );
    });

    test('constructor stores playback preview keys', () {
      final key = previewKey(0, 320, 180);
      expect(
        CacheInvalidationPlan(playbackPreviews: [key]).playbackPreviews,
        contains(key),
      );
    });

    test('constructor defensively copies input iterables', () {
      final keys = [layerKey(0, 0)];
      final plan = CacheInvalidationPlan(layerTiles: keys);
      keys.add(layerKey(1, 0));
      expect(plan.layerTiles.length, 1);
    });

    test('exposed key sets are unmodifiable', () {
      expect(
        () => CacheInvalidationPlan.empty().layerTiles.add(layerKey(0, 0)),
        throwsUnsupportedError,
      );
      expect(
        () => CacheInvalidationPlan.empty().frameComposites.add(frameKey(0)),
        throwsUnsupportedError,
      );
      expect(
        () => CacheInvalidationPlan.empty().playbackPreviews.add(
          previewKey(0, 1, 1),
        ),
        throwsUnsupportedError,
      );
    });

    test('isEmpty is true only when all key sets are empty', () {
      expect(CacheInvalidationPlan.empty().isEmpty, isTrue);
      expect(
        CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]).isEmpty,
        isFalse,
      );
      expect(
        CacheInvalidationPlan(frameComposites: [frameKey(0)]).isEmpty,
        isFalse,
      );
      expect(
        CacheInvalidationPlan(playbackPreviews: [previewKey(0, 1, 1)]).isEmpty,
        isFalse,
      );
    });

    test('isNotEmpty is true when any key set is non-empty', () {
      expect(CacheInvalidationPlan.empty().isNotEmpty, isFalse);
      expect(
        CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]).isNotEmpty,
        isTrue,
      );
    });

    test('totalKeyCount sums all key sets', () {
      expect(
        CacheInvalidationPlan(
          layerTiles: [layerKey(0, 0)],
          frameComposites: [frameKey(0)],
          playbackPreviews: [previewKey(0, 1, 1)],
        ).totalKeyCount,
        3,
      );
    });

    test('addLayerTile returns new plan', () {
      final original = CacheInvalidationPlan.empty();
      final next = original.addLayerTile(layerKey(0, 0));
      expect(next.layerTiles.length, 1);
      expect(original.layerTiles, isEmpty);
    });

    test('addFrameComposite returns new plan', () {
      final next = CacheInvalidationPlan.empty().addFrameComposite(frameKey(0));
      expect(next.frameComposites.length, 1);
    });

    test('addPlaybackPreview returns new plan', () {
      final next = CacheInvalidationPlan.empty().addPlaybackPreview(
        previewKey(0, 1, 1),
      );
      expect(next.playbackPreviews.length, 1);
    });

    test('add helpers do not mutate original', () {
      final original = CacheInvalidationPlan.empty();
      original.addLayerTiles([layerKey(0, 0)]);
      original.addFrameComposites([frameKey(0)]);
      original.addPlaybackPreviews([previewKey(0, 1, 1)]);
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

    test('addFrameComposites collapses duplicates', () {
      final key = frameKey(0);
      expect(
        CacheInvalidationPlan.empty()
            .addFrameComposites([key, key])
            .frameComposites
            .length,
        1,
      );
    });

    test('addPlaybackPreviews collapses duplicates', () {
      final key = previewKey(0, 1, 1);
      expect(
        CacheInvalidationPlan.empty()
            .addPlaybackPreviews([key, key])
            .playbackPreviews
            .length,
        1,
      );
    });

    test('merge combines all key sets', () {
      final merged = CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]).merge(
        CacheInvalidationPlan(
          frameComposites: [frameKey(0)],
          playbackPreviews: [previewKey(0, 1, 1)],
        ),
      );
      expect(merged.totalKeyCount, 3);
    });

    test('merge does not mutate originals', () {
      final a = CacheInvalidationPlan(layerTiles: [layerKey(0, 0)]);
      final b = CacheInvalidationPlan(frameComposites: [frameKey(0)]);
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

    test('fromDirtyTiles does not create FrameCompositeCacheKey entries', () {
      final plan = CacheInvalidationPlan.fromDirtyTiles(
        layerId: const LayerId('layer-a'),
        frameId: const FrameId('frame-a'),
        dirtyTiles: DirtyTileSet([TileCoord(x: 0, y: 0)]),
      );
      expect(plan.frameComposites, isEmpty);
    });

    test('fromDirtyTiles does not create PlaybackPreviewCacheKey entries', () {
      final plan = CacheInvalidationPlan.fromDirtyTiles(
        layerId: const LayerId('layer-a'),
        frameId: const FrameId('frame-a'),
        dirtyTiles: DirtyTileSet([TileCoord(x: 0, y: 0)]),
      );
      expect(plan.playbackPreviews, isEmpty);
    });

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
      final plan = CacheInvalidationPlan(
        layerTiles: [layerKey(0, 0)],
        frameComposites: [frameKey(0)],
        playbackPreviews: [previewKey(0, 1, 1)],
      );
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
        frameComposites: [
          frameKey(2),
          frameKey(1, cut: 'cut-b'),
          frameKey(1),
        ],
        playbackPreviews: [
          previewKey(1, 200, 100),
          previewKey(1, 100, 200),
          previewKey(0, 320, 180),
        ],
      );
      final json = plan.toJson();
      expect(
        (json['layerTiles'] as List).map(
          (e) => ((e as Map)['tileCoord'] as Map)['x'],
        ),
        [1, 2, 0, 1],
      );
      expect(
        (json['frameComposites'] as List).map((e) => (e as Map)['frameIndex']),
        [1, 2, 1],
      );
      expect(
        (json['playbackPreviews'] as List).map(
          (e) => ((e as Map)['previewSize'] as Map)['width'],
        ),
        [320, 100, 200],
      );
    });
  });
}
