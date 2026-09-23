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
      historyPolicy: const BrushHistoryPolicy(),
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
        sourceEffects: const [],
      );
      final quarter = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.quarter,
        sourceEffects: const [],
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
        sourceEffects: const [],
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
        sourceEffects: const [],
      );
      final second = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.half,
        sourceEffects: const [],
      );

      expect(identical(first, second), isTrue);
      expect(
        identical(
          cache.validImageOrNull(
            key('frame-a'),
            PlaybackQuality.half,
            canvasSize: canvasSize,
            sourceEffects: const [],
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
        sourceEffects: const [],
      );

      coordinator.commitSourceStroke(sourceDabs: [dab(x: 5, y: 5)]);

      expect(
        cache.validImageOrNull(
          key('frame-a'),
          PlaybackQuality.full,
          canvasSize: canvasSize,
          sourceEffects: const [],
        ),
        isNull,
      );
      final rebuilt = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      );
      expect(identical(first, rebuilt), isFalse);
      expect(
        identical(first!.content, rebuilt!.content),
        isFalse,
        reason: 'a new picture is new CONTENT — what a holder reads to know '
            'the display it composed with the old one is stale',
      );
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
          sourceEffects: const [],
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
        sourceEffects: const [],
      );
      await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.half,
        sourceEffects: const [],
      );
      expect(cache.estimatedBytes, greaterThan(0));

      cache.invalidateFrame(key('frame-a'));

      expect(cache.estimatedBytes, 0);
      cache.dispose();
    });
  });

  Future<List<int>> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  testWidgets('the FREE synchronous road: a cel that was not on screen is '
      'composed only when every tile already has its picture, at full '
      'quality — and no picture is made for it', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);
      final preview = BrushFrameDisplayCacheService(
        frameStore: store,
        canvasSize: canvasSize,
      ).prepareFramePreview(key('frame-a')).previewSurface;

      // Cold tiles: nothing pictured in the shared tile cache yet.
      expect(
        cache.prepareSyncOrNull(
          key: key('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: const [],
          makePictures: false,
        ),
        isNull,
      );
      expect(
        preview.tiles.values.every(
          (tile) => BitmapTileImageCache.instance.imageFor(tile) == null,
        ),
        isTrue,
        reason: 'asking the free road makes nothing',
      );

      // Pictured the way a canvas that painted them leaves them.
      for (final tile in preview.tiles.values) {
        BitmapTileImageCache.instance.pictureFor(tile);
      }
      expect(
        cache.prepareSyncOrNull(
          key: key('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.half,
          sourceEffects: const [],
          makePictures: false,
        ),
        isNull,
        reason: 'a level is not free: it is halvings on top of the compose',
      );

      final synced = cache.prepareSyncOrNull(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
        makePictures: false,
      );
      expect(synced, isNotNull);
      expect(synced!.image.width, 8);
      expect(
        identical(
          cache.validImageOrNull(
            key('frame-a'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          synced,
        ),
        isTrue,
        reason: 'the sync compose lands in the cache like prepare does',
      );
      cache.dispose();
    });
  });

  testWidgets('🚨a cel that WAS on screen is composed inside the call, cold '
      'tiles and all, at the quality asked — the same bytes the '
      'asynchronous road makes', (tester) async {
    await tester.runAsync(() async {
      for (final quality in PlaybackQuality.values) {
        final (store, _) = storeWithStroke();
        final cache = LayerFrameImageCache(frameStore: store);
        final reference = LayerFrameImageCache(frameStore: store);

        final now = cache.prepareSyncOrNull(
          key: key('frame-a'),
          canvasSize: canvasSize,
          quality: quality,
          sourceEffects: const [],
          makePictures: true,
        );
        expect(now, isNotNull, reason: '$quality: nothing to wait for');
        final later = await reference.prepare(
          key: key('frame-a'),
          canvasSize: canvasSize,
          quality: quality,
          sourceEffects: const [],
        );

        expect(now!.image.width, later!.image.width, reason: '$quality');
        expect(now.image.height, later.image.height, reason: '$quality');
        expect(now.worldRect, later.worldRect, reason: '$quality');
        expect(
          await bytesOf(now.image),
          await bytesOf(later.image),
          reason: '$quality: the two roads are one picture',
        );
        cache.dispose();
        reference.dispose();
      }
    });
  });

  testWidgets('a picture made inside the call is only that frame\'s: prepare '
      'answers with the plain snapshot that takes its place', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);

      final now = cache.prepareSyncOrNull(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.half,
        sourceEffects: const [],
        makePictures: true,
      )!;
      final nowBytes = await bytesOf(now.image);

      final kept = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.half,
        sourceEffects: const [],
      );
      expect(kept, isNotNull);
      expect(
        identical(kept!.image, now.image),
        isFalse,
        reason: 'the deferred image pins every tile picture it drew for as '
            'long as it lives; what a holder KEEPS is the snapshot',
      );
      expect(await bytesOf(kept.image), nowBytes, reason: 'the same picture');
      expect(kept.worldRect, now.worldRect);
      expect(
        identical(kept.content, now.content),
        isTrue,
        reason: 'the same CONTENT: the handle is all that changed, and a '
            'holder that composed with the deferred image keeps what it drew',
      );
      expect(
        identical(
          cache.validImageOrNull(
            key('frame-a'),
            PlaybackQuality.half,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          kept,
        ),
        isTrue,
        reason: 'and it is the entry now, under the same validity',
      );
      cache.dispose();
    });
  });

  testWidgets('a snapshot that lands after the cel moved on is let go, and '
      'prepare builds the cel as it is', (tester) async {
    await tester.runAsync(() async {
      final (store, coordinator) = storeWithStroke();
      final cache = LayerFrameImageCache(frameStore: store);

      cache.prepareSyncOrNull(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
        makePictures: true,
      );
      // An edit before the snapshot lands: the entry is stale either way.
      coordinator.commitSourceStroke(sourceDabs: [dab(x: 6, y: 6)]);

      final rebuilt = await cache.prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      );
      final reference = await LayerFrameImageCache(frameStore: store).prepare(
        key: key('frame-a'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      );
      expect(
        await bytesOf(rebuilt!.image),
        await bytesOf(reference!.image),
        reason: 'the cel WITH the second stroke — not the picture the '
            'snapshot was of',
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
        sourceEffects: const [],
      );
      final recent = await cache.prepare(
        key: key('frame-b'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      );

      // 8×8 RGBA = 256 bytes per image; keep room for exactly one.
      cache.evictLeastRecentlyUsed(targetBytes: 256);

      expect(
        cache.validImageOrNull(
          key('frame-a'),
          PlaybackQuality.full,
          canvasSize: canvasSize,
          sourceEffects: const [],
        ),
        isNull,
      );
      expect(
        identical(
          cache.validImageOrNull(
            key('frame-b'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          recent,
        ),
        isTrue,
      );
      cache.dispose();
    });
  });

  group('the ink alone', () {
    // 64×48 in tiles of 16, one dab in the tile at (32, 16): the ink is that
    // tile, the content the canvas.
    const inkCanvas = CanvasSize(width: 64, height: 48);
    const content = ui.Rect.fromLTWH(0, 0, 64, 48);

    BrushFrameStore storeWithInk() {
      final store = BrushFrameStore();
      BrushFrameEditingCoordinator(
        initialFrameKey: key('ink'),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: inkCanvas,
          tileSize: 16,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(sourceDabs: [dab(x: 40, y: 22)]);
      return store;
    }

    testWidgets('a row that draws exactly from its ink is stored as its ink — '
        'at every level, the same rect', (tester) async {
      await tester.runAsync(() async {
        final cache = LayerFrameImageCache(frameStore: storeWithInk());
        addTearDown(cache.dispose);
        for (final (quality, worldRect) in const [
          (PlaybackQuality.full, ui.Rect.fromLTWH(32, 16, 16, 16)),
          (PlaybackQuality.half, ui.Rect.fromLTWH(32, 16, 16, 16)),
          (PlaybackQuality.quarter, ui.Rect.fromLTWH(32, 16, 16, 16)),
        ]) {
          final image = (await cache.prepare(
            key: key('ink'),
            canvasSize: inkCanvas,
            quality: quality,
            sourceEffects: const [],
            inkSuffices: true,
          ))!;
          expect(image.isInk, isTrue, reason: '$quality');
          expect(image.worldRect, worldRect, reason: '$quality');
          expect(image.extent, content, reason: '$quality');
          expect(
            image.image.width,
            worldRect.width / (1 << quality.level),
            reason: '$quality: one texel per level pixel',
          );
        }
      });
    });

    testWidgets('a route that needs the whole image never gets the ink, and '
        'the whole image serves one that would take either', (tester) async {
      await tester.runAsync(() async {
        final cache = LayerFrameImageCache(frameStore: storeWithInk());
        addTearDown(cache.dispose);
        Future<LayerFrameImage> asked({required bool inkSuffices}) async =>
            (await cache.prepare(
              key: key('ink'),
              canvasSize: inkCanvas,
              quality: PlaybackQuality.full,
              sourceEffects: const [],
              inkSuffices: inkSuffices,
            ))!;
        expect((await asked(inkSuffices: true)).isInk, isTrue);
        final whole = await asked(inkSuffices: false);
        expect(whole.isInk, isFalse);
        expect(whole.worldRect, content);
        expect(whole.image.width, 64);
        expect(identical(await asked(inkSuffices: true), whole), isTrue);
      });
    });

    testWidgets('the sync road stores the ink too, and the snapshot that '
        'settles keeps both rects', (tester) async {
      await tester.runAsync(() async {
        final store = storeWithInk();
        final cache = LayerFrameImageCache(frameStore: store);
        addTearDown(cache.dispose);
        final now = cache.prepareSyncOrNull(
          key: key('ink'),
          canvasSize: inkCanvas,
          quality: PlaybackQuality.half,
          sourceEffects: const [],
          makePictures: true,
          inkSuffices: true,
        )!;
        expect(now.isInk, isTrue);
        expect(now.worldRect, const ui.Rect.fromLTWH(32, 16, 16, 16));
        final settled = (await cache.prepare(
          key: key('ink'),
          canvasSize: inkCanvas,
          quality: PlaybackQuality.half,
          sourceEffects: const [],
          inkSuffices: true,
        ))!;
        expect(identical(settled.image, now.image), isFalse,
            reason: 'fixture: the snapshot took the deferred image\'s place');
        expect(settled.worldRect, now.worldRect);
        expect(settled.extent, now.extent);
        expect(identical(settled.content, now.content), isTrue);
      });
    });
  });
}
