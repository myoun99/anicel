import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
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
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart' show TransformPose;
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/composite_tree.dart';

import '../helpers/placement_reading.dart';
import '../helpers/the_frame_as_it_stands.dart';

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
      historyPolicy: const BrushHistoryPolicy(),
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
          // A dab that COVERS: at 3단계 a 2px nib is all anti-alias edge
          // (I-50) and the row under it would show through.
          antiAlias: BrushAntiAlias.none,
        ),
      ],
    );
    return LayerFrameImageCache(frameStore: store);
  }

  testWidgets('paints drawn layers and skips undrawn ones', (tester) async {
    final cache = cacheWithStroke();
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TheFrameAsItStands(
            nodes: [
              CompositeLeaf<CanvasStackRow>(
                CanvasLayerImageRequest(
                  frameKey: key('layer-below'),
                  opacity: 0.5,
                ),
              ),
              CompositeLeaf<CanvasStackRow>(
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

    // It renders without errors; the undrawn layer resolves to nothing.
    expect(tester.takeException(), isNull);
  });

  // ↩️A layer entering the stack with a warm cache image painted in the SAME
  // frame (the layer-switch flicker), pinned here until no row was drawn as
  // its held image (one-picture-per-frame ②-5b-1): a frame as it stands
  // reads its cels in the build.

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
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      final image = await tester.runAsync(() async {
        final recorder = PictureRecorder();
        Canvas(recorder, const Rect.fromLTWH(0, 0, 6, 2)).drawRect(
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
                child: TheFrameAsItStands(
                  // Bottom → top: the active row, then a row above it.
                  nodes: [
                    const CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
                    CompositeLeaf<CanvasStackRow>(
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

    // 🚨a-marquee-on-a-posed-row (2026-09-25): the lift carries a posed
    // row's pixels OUT through its placement onto the canvas, where the box
    // moves them — so the float is canvas space, and the slot it draws in
    // sits under the row's pose wrap. Riding that wrap as it used to, a row
    // moved right by 2 showed its float 2 further right than its box.
    testWidgets('a POSED active row keeps the float where the box put it', (
      tester,
    ) async {
      final cache = cacheWithStroke();
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      final image = await tester.runAsync(() async {
        final recorder = PictureRecorder();
        Canvas(recorder, const Rect.fromLTWH(0, 0, 2, 2)).drawRect(
          const Rect.fromLTWH(0, 0, 2, 2),
          Paint()..color = const Color(0xFFFF0000),
        );
        return recorder.endRecording().toImage(2, 2);
      });
      addTearDown(image!.dispose);
      // The box put the float at canvas (2,0)-(4,2).
      float.value = SelectionFloatPaint(image: image, imageLeft: 2, imageTop: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey<String>('stack-capture'),
              child: SizedBox(
                width: 8,
                height: 8,
                child: TheFrameAsItStands(
                  nodes: [
                    CompositeLeaf<CanvasStackRow>(
                      CanvasActiveLayerRow(
                        opacity: 1,
                        // The row placed 2 to the right of where it is drawn.
                        placement: placedBy(
                          TransformPose(center: CanvasPoint(x: 6, y: 4)),
                          canvasSize,
                        ),
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

      expect(at(2, 0), [255, 0, 0], reason: 'the float is where its box is');
      expect(at(3, 1), [255, 0, 0]);
      expect(
        at(5, 0),
        isNot([255, 0, 0]),
        reason: 'and not placed a second time by the row\'s pose',
      );
      cache.dispose();
    });
  });
}
