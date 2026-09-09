// A PATCHED STEP CLEARS ITS DIRTY RECT BEFORE IT REPAINTS — TRANSLUCENT INK
// MUST NOT BLEND WITH ITS OWN PREVIOUS FRAME.
//
// A survivor of the mutation campaign (2026-09-04, the display-buffer
// cut): the `BlendMode.clear` before the dirty-rect repaint was dropped
// and every buffer test stayed green — their paper was opaque, so the
// composite drawn over the old pixels hid the double blend. This pin drives
// a LIVE stroke through the overlay model (the path the patch exists for),
// at half opacity on no paper, and compares the patched buffer with a cold
// composite of the same stroke, byte for byte.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/composite_tree.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushDab dabAt(double x, {int sequence = 0}) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  Future<void> pumpView(
    WidgetTester tester,
    BitmapSurfacePainter painter,
    DisplayBufferCache cache,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 8,
              height: 8,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasActiveLayerRow(opacity: 0.5),
                  ),
                ],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: painter,
                paintPaper: false,
                paperBackground: const ProjectBackground.color(0xFF00FF00),
                debugBufferCache: cache,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Uint8List> bytesNow(WidgetTester tester) async {
    final found = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;
    const size = Size(8, 8);
    final recorder = ui.PictureRecorder();
    found.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(8, 8);
    picture.dispose();
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  testWidgets('two dabs in one tile: the patched buffer equals a cold '
      'composite of the same stroke', (tester) async {
    final patched = DisplayBufferCache();
    addTearDown(patched.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    final painter = BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile.blank(
            size: 8,
          ),
        },
      ),
      overlayModel: overlay,
      showTransparentBackground: false,
    );
    await pumpView(tester, painter, patched);
    await bytesNow(tester);
    await bytesNow(tester);

    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2)], from: 0);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
      );
      await overlay.waitForPendingDecodes();
    });
    await bytesNow(tester);
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2), dabAt(5, sequence: 1)], from: 1);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 3, y: 2, width: 5, height: 5),
      );
      await overlay.waitForPendingDecodes();
    });
    final afterPatch = await bytesNow(tester);
    expect(
      patched.patchedCount,
      greaterThan(0),
      reason: 'fixture: the dabs composed through the patch path',
    );

    final cold = DisplayBufferCache();
    addTearDown(cold.dispose);
    await pumpView(tester, painter, cold);
    final fresh = await bytesNow(tester);
    expect(
      afterPatch,
      fresh,
      reason:
          'the dirty rect is cleared before its repaint — the first dab, '
          'drawn again over its own previous frame, would read darker',
    );
  });
}
