import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/composite_tree.dart';

/// 🚨A6 — HELD PIXELS ARE DECLARED PIXELS.
///
/// The editing canvas and the playback holders keep CLONES of cache
/// images, and a clone shares pixels: evicting the entry "freed" bytes
/// that stayed fully alive, so every budget figure downstream was fiction
/// — and eviction kept throwing away the very image on screen, the
/// "worked harder, got emptier" loop PR #1065 documented at the enforcer
/// level without being able to fix it at the cache level.
///
/// The pin is the holder telling the cache. Eviction refuses pinned
/// slots, and `pinnedBytes` is the MEASURED reserve that replaced the
/// session's estimate — the one that saturated at its clamp around
/// twenty layers and then reported the same number for five hundred.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey keyFor(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  BrushDab dab() => BrushDab(
    center: CanvasPoint(x: 1, y: 1),
    color: 0xFF000000,
    size: 2,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  BrushFrameStore storeWithStrokes(List<String> frameIds) {
    final store = BrushFrameStore();
    for (final frameId in frameIds) {
      BrushFrameEditingCoordinator(
        initialFrameKey: keyFor(frameId),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvasSize,
          tileSize: 4,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(sourceDabs: [dab()]);
    }
    return store;
  }

  group('layer frame image cache', () {
    testWidgets('eviction refuses a pinned slot and takes the rest',
        (tester) async {
      await tester.runAsync(() async {
        final cache = LayerFrameImageCache(
          frameStore: storeWithStrokes(['frame-a', 'frame-b']),
        );
        await cache.prepare(
          key: keyFor('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: const [],
        );
        await cache.prepare(
          key: keyFor('frame-b'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: const [],
        );

        cache.retainPin(keyFor('frame-a'), PlaybackQuality.full);
        cache.enforceBudget(maxBytes: 0);

        expect(
          cache.validImageOrNull(
            keyFor('frame-a'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          isNotNull,
          reason: 'the pinned slot is on screen — eviction must refuse it',
        );
        expect(
          cache.validImageOrNull(
            keyFor('frame-b'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          isNull,
          reason: 'the unpinned slot goes as before',
        );
        expect(
          cache.pinnedBytes,
          8 * 8 * 4,
          reason: 'the measured reserve is exactly the pinned image',
        );

        cache.releasePin(keyFor('frame-a'), PlaybackQuality.full);
        expect(cache.pinnedBytes, 0);
        cache.enforceBudget(maxBytes: 0);
        expect(
          cache.validImageOrNull(
            keyFor('frame-a'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          isNull,
          reason: 'released means evictable again',
        );
        cache.dispose();
      });
    });
  });

  group('the editing stack declares its clones', () {
    testWidgets('mounted: pinned; unmounted: released', (tester) async {
      final cache = LayerFrameImageCache(
        frameStore: storeWithStrokes(['frame-a']),
      );
      // Warm BEFORE mount, so the sync sweep adopts (and pins) at first
      // build — deterministic under the fake clock.
      await tester.runAsync(
        () => cache.prepare(
          key: keyFor('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: const [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 8,
              height: 8,
              child: CanvasLayerStackView(
                nodes: [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasLayerImageRequest(
                      frameKey: keyFor('frame-a'),
                      opacity: 1,
                    ),
                  ),
                ],
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        cache.pinnedBytes,
        8 * 8 * 4,
        reason: 'the stack holds a clone, so the cache must know — this is '
            'the measured reserve the enforcer reads',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(
        cache.pinnedBytes,
        0,
        reason: 'unmounting releases what mounting declared',
      );
      cache.dispose();
    });

    testWidgets('a swapped cache moves the pin — released where it was '
        'taken, retained where it will be released', (tester) async {
      final store = storeWithStrokes(['frame-a']);
      final oldCache = LayerFrameImageCache(frameStore: store);
      final newCache = LayerFrameImageCache(frameStore: store);
      await tester.runAsync(() async {
        await oldCache.prepare(
          key: keyFor('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: const [],
        );
        await newCache.prepare(
          key: keyFor('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: const [],
        );
      });

      Future<void> pumpWith(LayerFrameImageCache cache) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 8,
                height: 8,
                child: CanvasLayerStackView(
                  nodes: [
                    CompositeLeaf<CanvasStackRow>(
                      CanvasLayerImageRequest(
                        frameKey: keyFor('frame-a'),
                        opacity: 1,
                      ),
                    ),
                  ],
                  imageCache: cache,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpWith(oldCache);
      expect(oldCache.pinnedBytes, 8 * 8 * 4);

      await pumpWith(newCache);
      expect(
        oldCache.pinnedBytes,
        0,
        reason: 'the old cache must not carry a dead reserve forever',
      );
      expect(
        newCache.pinnedBytes,
        8 * 8 * 4,
        reason: 'the clone the stack still shows is declared on the cache '
            'the enforcer now reads',
      );

      // The whole chain stays balanced: unmount releases exactly what the
      // move retained (an unbalanced release asserts in debug).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(newCache.pinnedBytes, 0);
      oldCache.dispose();
      newCache.dispose();
    });

    testWidgets('an image let go before the cache is swapped is released on '
        'the cache that pinned it, in the build after', (tester) async {
      final store = storeWithStrokes(['frame-a', 'frame-b']);
      final oldCache = LayerFrameImageCache(frameStore: store);
      final newCache = LayerFrameImageCache(frameStore: store);
      await tester.runAsync(() async {
        for (final cache in [oldCache, newCache]) {
          for (final frameId in ['frame-a', 'frame-b']) {
            await cache.prepare(
              key: keyFor(frameId),
              canvasSize: canvasSize,
              quality: PlaybackQuality.full,
              sourceEffects: const [],
            );
          }
        }
      });

      Future<void> pumpWith(LayerFrameImageCache cache) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 8,
              height: 8,
              child: CanvasLayerStackView(
                nodes: [
                  for (final frameId in ['frame-a', 'frame-b'])
                    CompositeLeaf<CanvasStackRow>(
                      CanvasLayerImageRequest(
                        frameKey: keyFor(frameId),
                        opacity: 1,
                      ),
                    ),
                ],
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
              ),
            ),
          ),
        ),
      );

      await pumpWith(oldCache);
      await tester.pumpAndSettle();
      expect(oldCache.pinnedBytes, 2 * 8 * 8 * 4);

      // frame-b becomes a copy of frame-a's very surface: the view holds
      // a's picture under b too, and lets go of what it held for b — out of
      // any build, so it waits for the next one, pinned on the old cache.
      store.storeCopiedSurface(
        keyFor('frame-b'),
        store.bakedSurfaceOrNull(keyFor('frame-a'))!,
        source: keyFor('frame-a'),
      );
      // That build swaps the cache: the pins of what the view holds move,
      // and what it let go is released where it was pinned — on the new
      // cache it would be a release of a pin that cache never saw, and
      // the old one would keep it for ever.
      await pumpWith(newCache);
      await tester.pumpAndSettle();
      expect(oldCache.pinnedBytes, 0);

      // Balanced to the end: unmount releases on the new cache exactly what
      // it holds there (an unbalanced release asserts in debug).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(newCache.pinnedBytes, 0);
      oldCache.dispose();
      newCache.dispose();
    });
  });
}
