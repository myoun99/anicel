import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
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
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
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

  // 🚨TS1 (유저: 변형 도중에 다른 레이어에 그려진 게 무시되서 라이브로 안보임.
  // 즉 변형중인 레이어 위에 흰 선으로 그린게있으면, 변형중에도 그 선에 의해
  // 흰색으로 가려져야하는데 안가려짐. 확정시키고 나야 가려진게 적용됨).
  //
  // The float used to be a widget ABOVE this whole picture, so no row could
  // occlude it. This is the pixel that says it is inside the picture now, at
  // the active row's depth — one that the row above covers, and one beside it
  // that only the float reaches.
  group('the selection float draws at the ACTIVE layer depth', () {
    Future<Uint8List> capture(WidgetTester tester) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey<String>('stack-capture')),
      );
      final image = boundary.toImageSync();
      late Uint8List bytes;
      await tester.runAsync(() async {
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        bytes = Uint8List.fromList(data!.buffer.asUint8List());
      });
      image.dispose();
      return bytes;
    }

    testWidgets('a row above covers it; a row below does not', (tester) async {
      // The layer image is a black 2×2 dab at canvas (0,0)-(2,2) — the ROW
      // ABOVE the active one. The float is a red rectangle over (0,0)-(6,2),
      // so it reaches both under that dab and past it.
      final cache = cacheWithStroke();
      const quality = PlaybackQuality.full;
      await tester.runAsync(
        () => cache.prepare(
          key: key('layer-below'),
          canvasSize: canvasSize,
          quality: quality,
        ),
      );
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      final image = await tester.runAsync(() async {
        final recorder = PictureRecorder();
        Canvas(recorder, const Rect.fromLTWH(0, 0, 6, 2))
          ..drawRect(
            const Rect.fromLTWH(0, 0, 6, 2),
            Paint()..color = const Color(0xFFFF0000),
          );
        return recorder.endRecording().toImage(6, 2);
      });
      addTearDown(image!.dispose);
      float.value = SelectionFloatPaint(image: image, imageLeft: 0, imageTop: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey<String>('stack-capture'),
              child: SizedBox(
                width: 8,
                height: 8,
                child: CanvasLayerStackView(
                  // Bottom → top: the active row, then a row above it.
                  nodes: [
                    const CanvasActiveLayerNode(opacity: 1),
                    CanvasLayerImageNode(
                      CanvasLayerImageRequest(
                        frameKey: key('layer-below'),
                        opacity: 1,
                      ),
                    ),
                  ],
                  activeSurfacePainter: BitmapSurfacePainter(
                    surface: BitmapSurface(canvasSize: canvasSize, tileSize: 4),
                    viewport: CanvasViewport(),
                    showTransparentBackground: false,
                  ),
                  floatOverlay: float,
                  imageCache: cache,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  paintPaper: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pixels = await capture(tester);
      List<int> at(int x, int y) {
        final offset = (y * 8 + x) * 4;
        return pixels.sublist(offset, offset + 3);
      }

      expect(
        at(0, 0),
        [0, 0, 0],
        reason: 'the row ABOVE the active one covers the float',
      );
      expect(
        at(4, 0),
        [255, 0, 0],
        reason: 'and where nothing is above it, the float shows',
      );
      cache.dispose();
    });
  });
}
