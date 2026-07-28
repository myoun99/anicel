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
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey key(String layerId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: LayerId(layerId),
    frameId: const FrameId('frame'),
  );

  LayerFrameImageCache cacheWithStroke() {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: key('layer-below'),
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
    return LayerFrameImageCache(frameStore: store);
  }

  testWidgets('paints drawn layers and skips undrawn ones', (tester) async {
    final cache = cacheWithStroke();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasLayerStackView(
            nodes: [
              CanvasLayerImageNode(
                CanvasLayerImageRequest(
                  frameKey: key('layer-below'),
                  opacity: 0.5,
                ),
              ),
              CanvasLayerImageNode(
                CanvasLayerImageRequest(
                  frameKey: key('layer-undrawn'),
                  opacity: 1,
                ),
              ),
            ],
            imageCache: cache,
            canvasSize: canvasSize,
            viewport: CanvasViewport(zoom: 2),
            paintPaper: true,
          ),
        ),
      ),
    );
    // Let the async image preparation finish.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    // Paint-only (input passes through) and it renders without errors; the
    // undrawn layer resolves to nothing.
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(tester.takeException(), isNull);
    cache.dispose();
  });

  testWidgets('a layer entering the stack with a warm cache image paints '
      'in the SAME frame (layer-switch flicker regression)', (tester) async {
    final cache = cacheWithStroke();
    const quality = PlaybackQuality.full;
    // Warm the cache the way the prerender does after every stroke.
    await tester.runAsync(
      () => cache.prepare(
        key: key('layer-below'),
        canvasSize: canvasSize,
        quality: quality,
      ),
    );

    Widget stack(List<CanvasLayerImageRequest> layers) => MaterialApp(
      home: Scaffold(
        body: CanvasLayerStackView(
          nodes: [for (final layer in layers) CanvasLayerImageNode(layer)],
          imageCache: cache,
          canvasSize: canvasSize,
          viewport: CanvasViewport(),
        ),
      ),
    );

    int paintedImages() {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(CanvasLayerStackView),
          matching: find.byType(CustomPaint),
        ),
      );
      // The painter walks a TREE now; this stack is flat, so its top level
      // is exactly the resolved images.
      final nodes = (paint.painter as dynamic).nodes as List<Object?>;
      return nodes.length;
    }

    // The layer starts OUTSIDE the stack (it is the active layer, drawn by
    // the interactive view).
    await tester.pumpWidget(stack(const []));
    expect(paintedImages(), 0);

    // The layer switch: it enters the stack. The warm image must paint on
    // this very pump — the async-only path painted it a frame late and the
    // artwork visibly vanished and reappeared.
    await tester.pumpWidget(
      stack([
        CanvasLayerImageRequest(frameKey: key('layer-below'), opacity: 1),
      ]),
    );
    expect(
      paintedImages(),
      1,
      reason: 'warm images must adopt synchronously on layer switch',
    );

    // Switching back removes it the same frame (no double-draw under the
    // interactive view).
    await tester.pumpWidget(stack(const []));
    expect(paintedImages(), 0);

    cache.dispose();
  });
}
