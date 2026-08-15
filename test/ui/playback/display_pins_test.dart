import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

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
        historyPolicy: const BrushHistoryPolicy(
          userUndoLimit: 8,
          deferredBakeRatio: 0,
        ),
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
        );
        await cache.prepare(
          key: keyFor('frame-b'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
        );

        cache.retainPin(keyFor('frame-a'), PlaybackQuality.full);
        cache.evictLeastRecentlyUsed(targetBytes: 0);

        expect(
          cache.validImageOrNull(
            keyFor('frame-a'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
          ),
          isNotNull,
          reason: 'the pinned slot is on screen — eviction must refuse it',
        );
        expect(
          cache.validImageOrNull(
            keyFor('frame-b'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
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
        cache.evictLeastRecentlyUsed(targetBytes: 0);
        expect(
          cache.validImageOrNull(
            keyFor('frame-a'),
            PlaybackQuality.full,
            canvasSize: canvasSize,
          ),
          isNull,
          reason: 'released means evictable again',
        );
        cache.dispose();
      });
    });
  });

  group('cut frame composite cache', () {
    Cut cut() => Cut(
      id: const CutId('cut'),
      name: 'Cut',
      duration: 4,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: const LayerId('layer'),
          name: 'A',
          frames: [
            Frame(
              id: const FrameId('frame-a'),
              duration: 1,
              strokes: const [],
            ),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('frame-a'), length: 2),
          },
        ),
      ],
    );

    CutFrameCompositeCache compositeCache() {
      final store = storeWithStrokes(['frame-a']);
      return CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: (cut, layerId, frameId) => BrushFrameKey(
          projectId: const ProjectId('project'),
          trackId: const TrackId('track'),
          cutId: cut.id,
          layerId: layerId,
          frameId: frameId,
        ),
      );
    }

    testWidgets('a pinned frame survives a zero-budget enforcement',
        (tester) async {
      await tester.runAsync(() async {
        final cache = compositeCache();
        await cache.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        );
        await cache.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.half,
        );

        cache.retainPin((const CutId('cut'), 0, PlaybackQuality.full));
        cache.enforceBudget(maxBytes: 0);

        expect(
          cache.validCompositeOrNull(
            cut: cut(),
            frameIndex: 0,
            quality: PlaybackQuality.full,
          ),
          isNotNull,
          reason: 'the held frame is on screen through a clone — evicting '
              'it returns no bytes and re-composites the exact picture '
              'being shown',
        );
        expect(
          cache.validCompositeOrNull(
            cut: cut(),
            frameIndex: 0,
            quality: PlaybackQuality.half,
          ),
          isNull,
          reason: 'the unpinned tier goes',
        );
        cache.releasePin((const CutId('cut'), 0, PlaybackQuality.full));
        cache.dispose();
      });
    });

    testWidgets('pinnedBytes counts a shared image once — held exposures '
        'share one image under many keys', (tester) async {
      await tester.runAsync(() async {
        final cache = compositeCache();
        // Frames 0 and 1 are one held exposure: equal signatures, one
        // stored image, two index keys.
        await cache.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        );
        await cache.prepareComposite(
          cut: cut(),
          frameIndex: 1,
          quality: PlaybackQuality.full,
        );

        cache.retainPin((const CutId('cut'), 0, PlaybackQuality.full));
        cache.retainPin((const CutId('cut'), 1, PlaybackQuality.full));
        expect(
          cache.pinnedBytes,
          8 * 8 * 4,
          reason: 'two pinned keys, one image — the reserve must not '
              'double-bill content addressing',
        );
        cache.releasePin((const CutId('cut'), 0, PlaybackQuality.full));
        cache.releasePin((const CutId('cut'), 1, PlaybackQuality.full));
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
                  CanvasLayerImageNode(
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
        );
        await newCache.prepare(
          key: keyFor('frame-a'),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
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
                    CanvasLayerImageNode(
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
  });
}
