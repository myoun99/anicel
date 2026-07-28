import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
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
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_cache_budget.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  // 8×8 RGBA = 256 bytes per full-quality image.
  const fullImageBytes = 8 * 8 * 4;

  BrushFrameKey frameKey(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      );

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
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('frame-a'), length: 1),
        },
      ),
    ],
  );

  ({LayerFrameImageCache layers, CutFrameCompositeCache composites}) caches() {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
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
    ).commitSourceStroke(
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
    final layers = LayerFrameImageCache(frameStore: store);
    return (
      layers: layers,
      composites: CutFrameCompositeCache(
        layerImages: layers,
        frameStore: store,
        frameKeyOf: frameKey,
      ),
    );
  }

  testWidgets(
    'layer images shrink into what the composites leave of the budget',
    (tester) async {
      await tester.runAsync(() async {
        final c = caches();
        await c.composites.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        );
        // The composite build also cached the full-quality layer image.
        expect(c.layers.estimatedBytes, fullImageBytes);
        expect(c.composites.estimatedBytes, fullImageBytes);

        PlaybackCacheBudgetEnforcer(
          layerImages: c.layers,
          composites: c.composites,
          maxBytes: fullImageBytes,
        ).enforce(
          protect: const [
            PlaybackProtectedRange(
              cutId: CutId('cut'),
              startFrame: 0,
              endFrame: 3,
              quality: PlaybackQuality.full,
            ),
          ],
        );

        // Composites fit the budget exactly; nothing remains for the layer
        // image cache.
        expect(c.composites.estimatedBytes, fullImageBytes);
        expect(c.layers.estimatedBytes, 0);
        c.composites.dispose();
        c.layers.dispose();
      });
    },
  );

  testWidgets('unprotected composites are evicted before protected ones', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final c = caches();
      final protectedImage = await c.composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      await c.composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.half,
      );

      PlaybackCacheBudgetEnforcer(
        layerImages: c.layers,
        composites: c.composites,
        maxBytes: fullImageBytes,
      ).enforce(
        protect: const [
          PlaybackProtectedRange(
            cutId: CutId('cut'),
            startFrame: 0,
            endFrame: 3,
            quality: PlaybackQuality.full,
          ),
        ],
      );

      expect(
        identical(
          c.composites.validCompositeOrNull(
            cut: cut(),
            frameIndex: 0,
            quality: PlaybackQuality.full,
          ),
          protectedImage,
        ),
        isTrue,
      );
      expect(
        c.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.half,
        ),
        isNull,
      );
      c.composites.dispose();
      c.layers.dispose();
    });
  });
}
