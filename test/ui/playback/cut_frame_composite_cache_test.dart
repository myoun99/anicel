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
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';
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

  Cut cut({double opacity = 1, TransformTrack? transformTrack}) => Cut(
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
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 24),
        },
        opacity: opacity,
        transformTrack: transformTrack,
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
      historyPolicy: const BrushHistoryPolicy(),
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
      );
      final held = await cache.prepareComposite(
        cut: cut(),
        frameIndex: 7,
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
        ),
        cache.prepareComposite(
          cut: cut(),
          frameIndex: 7,
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
        shouldAbort: () => true,
      );
      expect(aborted, isNull);
      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
        ),
        isNull,
        reason: 'an abandoned build must leave no cache entry behind',
      );

      final completed = await cache.prepareCompositeInterruptible(
        cut: cut(),
        frameIndex: 0,
        shouldAbort: () => false,
      );
      expect(completed, isNotNull);
      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
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
      );
      expect(
        cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
        ),
        isNotNull,
      );

      expect(
        cache.validCompositeOrNull(
          cut: cut(opacity: 0.5),
          frameIndex: 0,
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
        ),
        isNull,
      );
      cache.dispose();
    });
  });

  testWidgets('heldSignature hands back the key the composite is filed '
      'under, and files none of its own', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      final held = cut();
      await cache.prepareComposite(
        cut: held,
        frameIndex: 0,
      );
      CutFrameCompositeSignature? heldAt(int frameIndex) =>
          cache.heldSignature(
            cache.signatureOf(
              cut: held,
              frameIndex: frameIndex,
            ),
          );

      expect(
        heldAt(5),
        isNotNull,
        reason: 'frame 5 holds the same cel — the one image answers it',
      );
      expect(
        identical(heldAt(5), heldAt(7)),
        isTrue,
        reason: 'two fresh signatures of one picture get the ONE filed key '
            'back — what lets the green bar\'s next ask be `identical`',
      );
      // A screen showing frame 5 keeps the image only if frame 5 is one of
      // the slots it is filed under.
      cache.retainPin((const CutId('cut'), 5));
      cache.enforceBudget(maxBytes: 0);

      expect(
        heldAt(5),
        isNull,
        reason: 'only frame 0 filed a key — a read that filed frame 5 '
            'would have let the pin keep the image',
      );
      cache.releasePin((const CutId('cut'), 5));
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

  /// 유저 2026-10-08 (「4 허용치도 해결」): what a full cache keeps is what
  /// is wanted soonest. ↩️A `protect` list of frame ranges was passed over
  /// here whatever the cap said.
  testWidgets('a full cache lets go of the picture wanted latest, and makes '
      'room only out of pictures wanted later than the one it is for', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      const picture = 8 * 8 * 4;

      // Three pictures: the drawing (wanted now), the nothing past it
      // (wanted thirty frames on), and the drawing as it was before an edit
      // — which no frame wants. Made in that order, so recency says the
      // opposite.
      final wantedNow = await cache.prepareComposite(cut: cut(), frameIndex: 0);
      await cache.prepareComposite(cut: cut(), frameIndex: 30);
      await cache.prepareComposite(cut: cut(opacity: 0.5), frameIndex: 12);
      expect(cache.estimatedBytes, 3 * picture);
      int? stepOf(CutId cutId, int frameIndex) => switch (frameIndex) {
        0 => 0,
        30 => 30,
        _ => null,
      };
      bool held(int frameIndex, {double opacity = 1}) =>
          cache.validCompositeOrNull(
            cut: cut(opacity: opacity),
            frameIndex: frameIndex,
          ) !=
          null;

      expect(
        cache.enforceBudget(maxBytes: 2 * picture, stepOf: stepOf),
        isTrue,
      );
      expect(
        [held(0), held(30), held(12, opacity: 0.5)],
        [true, true, false],
        reason: 'what nobody wants goes first',
      );

      expect(
        cache.enforceBudget(maxBytes: 0, stepOf: stepOf, laterThan: 10),
        isFalse,
        reason: 'the picture wanted now is not room for one wanted ten on',
      );
      expect([held(0), held(30)], [true, false]);
      expect(
        identical(
          cache.validCompositeOrNull(cut: cut(), frameIndex: 0),
          wantedNow,
        ),
        isTrue,
      );

      expect(
        cache.enforceBudget(maxBytes: 0, stepOf: stepOf),
        isTrue,
        reason: 'with no such floor, a cap is a cap',
      );
      expect(cache.estimatedBytes, 0);
      cache.dispose();
    });
  });

  testWidgets('among pictures wanted equally, the one used longest ago '
      'goes first', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      await cache.prepareComposite(cut: cut(), frameIndex: 0);
      await cache.prepareComposite(cut: cut(), frameIndex: 30);
      // The first is asked again: the second is the one used longest ago.
      cache.validCompositeOrNull(cut: cut(), frameIndex: 0);

      cache.enforceBudget(maxBytes: 8 * 8 * 4);

      expect(cache.validCompositeOrNull(cut: cut(), frameIndex: 0), isNotNull);
      expect(cache.validCompositeOrNull(cut: cut(), frameIndex: 30), isNull);
      cache.dispose();
    });
  });

  // Where a row lies is laid on at composite time, and until this nothing
  // in the file moved one: every picture above is the same with the
  // placement left out.
  testWidgets('a MOVED row is composited where it lies', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      // The stroke inks artwork 0..2 both ways. The row lies half the canvas
      // right and down, so it shows over canvas 4..6.
      final moved = cut(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 8, y: 8),
          ),
        ),
      );
      Future<int> alphaAt(CanvasPoint canvas) async {
        final image = await cache.prepareComposite(cut: moved, frameIndex: 0);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final x = canvas.x.floor();
        final y = canvas.y.floor();
        return data!.getUint8((y * image.width + x) * 4 + 3);
      }

      expect(await alphaAt(CanvasPoint(x: 4.5, y: 4.5)), greaterThan(0));
      expect(await alphaAt(CanvasPoint(x: 0.5, y: 0.5)), 0);
      cache.dispose();
    });
  });

  // 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
  // 반전)」. Keyed from 100 to −100, the frame halfway is a scale of zero:
  // the row is not drawn there, as After Effects does not draw one.
  testWidgets('a row scaled to NOTHING on an axis is composited as nothing '
      '— the frame a flip passes through', (tester) async {
    await tester.runAsync(() async {
      final (store, _) = storeWithStroke();
      final cache = cacheFor(store);
      final flipping = cut(
        transformTrack: TransformTrack.empty().copyWith(
          scale: PropertyTrack<CanvasPoint>.empty()
              .withKey(0, CanvasPoint(x: 1, y: 1))
              .withKey(2, CanvasPoint(x: -1, y: 1)),
        ),
      );
      Future<bool> inked(int frameIndex) async {
        final image = await cache.prepareComposite(
          cut: flipping,
          frameIndex: frameIndex,
        );
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return data!.buffer.asUint8List().any((byte) => byte != 0);
      }

      expect(await inked(0), isTrue, reason: 'fixture: the row has ink');
      expect(await inked(1), isFalse, reason: 'halfway: nothing across');
      expect(await inked(2), isTrue, reason: 'and flipped, it is back');
      cache.dispose();
    });
  });
}
