import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
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
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey frameKey(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      );

  Cut cut({double opacity = 1}) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 24,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('frame-a'), length: 24),
        },
        opacity: opacity,
      ),
    ],
  );

  (BrushFrameStore, BrushFrameEditingCoordinator) storeWithStroke() {
    final store = BrushFrameStore();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: frameKey(
        cut(),
        const LayerId('layer'),
        const FrameId('frame-a'),
      ),
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
    coordinator.commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 1, y: 1),
          color: 0xFF000000,
          size: 2,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    return (store, coordinator);
  }

  CutFrameCompositeCache cacheFor(BrushFrameStore store) {
    return CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
  }

  testWidgets('held frames share one composite image', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);

      final atZero = await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      final held = await cache.prepareComposite(
        cut: cut(),
        frameIndex: 7,
        quality: PlaybackQuality.full,
      );

      expect(identical(atZero, held), isTrue);
      // Content addressing: two index entries, one stored image.
      expect(cache.estimatedBytes, 8 * 8 * 4);
      cache.dispose();
    });
  });

  testWidgets('CONCURRENT prepares for one signature keep the first store '
      '(the check-then-store race): both callers land on the same image '
      'and the loser compose is disposed, never orphaned', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);

      // Frames 0 and 7 sit inside ONE held exposure → equal signatures.
      // Both prepares start before either stores (the parked track stack
      // scrubbing across a held exposure, or on-demand racing the
      // warmer): the second store used to overwrite the first entry,
      // orphaning it with a live reference count — an image nothing could
      // ever release.
      final images = await Future.wait([
        cache.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        ),
        cache.prepareComposite(
          cut: cut(),
          frameIndex: 7,
          quality: PlaybackQuality.full,
        ),
      ]);

      expect(identical(images[0], images[1]), isTrue);
      // One stored image, both index keys valid against it.
      expect(cache.estimatedBytes, 8 * 8 * 4);
      for (final frameIndex in const [0, 7]) {
        expect(
          cache.validCompositeOrNull(
            cut: cut(),
            frameIndex: frameIndex,
            quality: PlaybackQuality.full,
          ),
          isNotNull,
        );
      }
      cache.dispose();
    });
  });

  testWidgets('an interruptible prepare finishing after dispose retires '
      'its image instead of caching into the disposed maps', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);

      final pending = cache.prepareCompositeInterruptible(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
        shouldAbort: () => false,
      );
      cache.dispose();

      expect(await pending, isNull, reason: 'nothing cached after teardown');
      expect(cache.estimatedBytes, 0);
    });
  });

  testWidgets('pasteboard content stays OUT of the composite: adding an '
      'off-canvas stroke leaves the canvas-cropped bytes identical', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<Uint8List> compositeBytes(BrushFrameStore store) async {
        final cache = cacheFor(store);
        final image = await cache.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        );
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        cache.dispose();
        return data!.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      }

      final (plainStore, _) = storeWithStroke();
      final reference = await compositeBytes(plainStore);

      final (pasteboardStore, coordinator) = storeWithStroke();
      // A stroke fully OFF the canvas (8×8 canvas → dab at (-2, -2)
      // paints only negative coords).
      coordinator.commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: -2, y: -2),
            color: 0xFF00FF00,
            size: 2,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );
      final withPasteboard = await compositeBytes(pasteboardStore);

      expect(
        withPasteboard,
        reference,
        reason:
            'the composite rasters at canvas size — off-canvas artwork '
            'must neither leak in nor shift the on-canvas pixels',
      );
    });
  });

  testWidgets('an interrupted composite caches nothing and a quiet retry '
      'completes (R13-3)', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);

      final aborted = await cache.prepareCompositeInterruptible(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
        shouldAbort: () => true,
      );
      expect(aborted, isNull);
      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        ),
        isNull,
        reason: 'an abandoned build must leave no cache entry behind',
      );

      final completed = await cache.prepareCompositeInterruptible(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
        shouldAbort: () => false,
      );
      expect(completed, isNotNull);
      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        ),
        isNotNull,
      );
      cache.dispose();
    });
  });

  testWidgets('layer opacity change invalidates without any sink event', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        ),
        isNotNull,
      );

      expect(
        cache.validCompositeOrNull(
          cut: cut(opacity: 0.5),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        ),
        isNull,
      );
      cache.dispose();
    });
  });

  testWidgets('a brush commit invalidates via source revision', (tester) async {
    await tester.runAsync(() async {
      final (store, coordinator) = storeWithStroke();
      final cache = cacheFor(store);
      await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );

      coordinator.commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: 5, y: 5),
            color: 0xFF000000,
            size: 2,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );

      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        ),
        isNull,
      );
      cache.dispose();
    });
  });

  testWidgets('camera keyframe changes do NOT invalidate composites', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      final image = await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );

      final withCamera = cut().copyWith(
        camera: CutCamera(
          keyframes: {0: CameraPose(center: CanvasPoint(x: 4, y: 4), zoom: 2)},
        ),
      );

      expect(
        identical(
          cache.validCompositeOrNull(
            cut: withCamera,
            frameIndex: 0,
            quality: PlaybackQuality.full,
          ),
          image,
        ),
        isTrue,
      );
      cache.dispose();
    });
  });

  testWidgets('invalidateWhereLayerFrame drops matching composites', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      expect(cache.estimatedBytes, greaterThan(0));

      cache.invalidateWhereLayerFrame(
        layerId: const LayerId('layer'),
        frameId: const FrameId('frame-a'),
      );

      expect(cache.estimatedBytes, 0);
      cache.dispose();
    });
  });

  testWidgets('budget eviction never touches the protected range', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, coordinator) = storeWithStroke();
      final cache = cacheFor(store);

      final protectedImage = await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      // A second, different composite (new stroke on a different frame id
      // exposed at index 12 via a second layer entry isn't needed — reuse a
      // different quality to create a distinct image).
      await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.half,
      );
      expect(cache.estimatedBytes, greaterThan(8 * 8 * 4));

      cache.enforceBudget(
        maxBytes: 8 * 8 * 4,
        protect: const [
          PlaybackProtectedRange(
            cutId: CutId('cut'),
            startFrame: 0,
            endFrame: 23,
            quality: PlaybackQuality.full,
          ),
        ],
      );

      expect(
        identical(
          cache.validCompositeOrNull(
            cut: cut(),
            frameIndex: 0,
            quality: PlaybackQuality.full,
          ),
          protectedImage,
        ),
        isTrue,
      );
      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.half,
        ),
        isNull,
      );
      cache.dispose();
    });
  });
}
