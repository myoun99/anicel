import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey key(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  BrushDab dab({double x = 1, double y = 1}) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF000000,
    size: 2,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  (BrushFrameStore, BrushFrameEditingCoordinator) storeWithStroke() {
    final store = BrushFrameStore();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: key('frame-a'),
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    );
    coordinator.commitSourceStroke(sourceDabs: [dab()]);
    return (store, coordinator);
  }

  testWidgets('prepare renders at the quality raster size', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);

      final full = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );
      final quarter = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.quarter,
      );

      expect(full!.image.width, 8);
      expect(full.image.height, 8);
      expect(full.worldRect, const ui.Rect.fromLTWH(0, 0, 8, 8));
      expect(quarter!.image.width, 2);
      expect(quarter.image.height, 2);
      expect(
        quarter.worldRect,
        const ui.Rect.fromLTWH(0, 0, 8, 8),
        reason: 'the world rect stays canvas-space at every quality',
      );
      cache.dispose();
    });
  });

  testWidgets('a cel with pasteboard content grows the image extent and '
      'reports it through worldRect', (tester) async {
    await tester.runAsync(() async {
      final (store, coordinator) = storeWithStroke();
      // Canvas 8×8, tile 4 → a dab at (-2, -2) lands on tile (-1, -1):
      // pixels in [-3, -1]², extent grows to the tile rect [-4, 0)².
      coordinator.commitSourceStroke(sourceDabs: [dab(x: -2, y: -2)]);
      final cache = LayerFrameImageCache(frameStore: store);

      final positioned = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );

      expect(positioned!.worldRect, const ui.Rect.fromLTRB(-4, -4, 8, 8));
      expect(positioned.image.width, 12);
      expect(positioned.image.height, 12);
      cache.dispose();
    });
  });

  testWidgets('second prepare is a cache hit returning the same image', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);

      final first = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.half,
      );
      final second = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.half,
      );

      expect(identical(first, second), isTrue);
      expect(
        identical(
          cache.validImageOrNull(
            key('frame-a'),
            PlaybackQuality.half,
            canvasSize: canvasSize,
          ),
          first,
        ),
        isTrue,
      );
      cache.dispose();
    });
  });

  testWidgets('a new stroke commit invalidates via source revision', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, coordinator) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);

      final first = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );

      coordinator.commitSourceStroke(sourceDabs: [dab(x: 5, y: 5)]);

      expect(
        cache.validImageOrNull(
          key('frame-a'),
          PlaybackQuality.full,
          canvasSize: canvasSize,
        ),
        isNull,
      );
      final rebuilt = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );
      expect(identical(first, rebuilt), isFalse);
      cache.dispose();
    });
  });

  testWidgets('undrawn frames yield null', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);

      expect(
        await cache.prepare(
          key: key('frame-undrawn'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
        ),
        isNull,
      );
      cache.dispose();
    });
  });

  testWidgets('invalidateFrame drops all qualities', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);
      await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );
      await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.half,
      );
      expect(cache.estimatedBytes, greaterThan(0));

      cache.invalidateFrame(key('frame-a'));

      expect(cache.estimatedBytes, 0);
      cache.dispose();
    });
  });

  testWidgets('prepareSyncOrNull composes synchronously from decoded tiles '
      'and falls back to null on cold tiles (layer-switch handoff)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);

      // Cold tiles: nothing decoded in the shared tile cache yet.
      expect(
        cache.prepareSyncOrNull(
          key: key('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
        ),
        isNull,
      );

      // Decode the frame's tiles the way the on-screen editing canvas
      // keeps them (the just-deactivated layer's tiles are always warm).
      final preview = BrushFrameDisplayCacheService(
        frameStore: store,
        canvasSize: canvasSize,
      ).prepareFramePreview(key('frame-a')).previewSurface;
      for (final tile in preview.tiles.values) {
        BitmapTileImageCache.instance.ensureDecoded(tile);
      }
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!BitmapTileImageCache.instance.allDecoded(preview.tiles.values)) {
        expect(DateTime.now().isBefore(deadline), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final synced = cache.prepareSyncOrNull(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );
      expect(synced, isNotNull);
      expect(synced!.image.width, 8);
      expect(
        identical(
          cache.validImageOrNull(
            key('frame-a'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
          ),
          synced,
        ),
        isTrue,
        reason: 'the sync compose lands in the cache like prepare does',
      );
      cache.dispose();
    });
  });

  testWidgets('LRU eviction keeps the most recently used entries', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, coordinator) = storeWithStroke();
      coordinator.selectFrame(key('frame-b'));
      coordinator.commitSourceStroke(sourceDabs: [dab(x: 6, y: 6)]);
      final cache = LayerFrameImageCache(frameStore: store);

      await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );
      final recent = await cache.prepare(
        key: key('frame-b'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      );

      // 8×8 RGBA = 256 bytes per image; keep room for exactly one.
      cache.evictLeastRecentlyUsed(targetBytes: 256);

      expect(
        cache.validImageOrNull(
          key('frame-a'),
          PlaybackQuality.full,
          canvasSize: canvasSize,
        ),
        isNull,
      );
      expect(
        identical(
          cache.validImageOrNull(
            key('frame-b'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
          ),
          recent,
        ),
        isTrue,
      );
      cache.dispose();
    });
  });
}
