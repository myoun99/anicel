import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨(v) — a floating selection moves under the hand, and the composite
/// buffer must never be kept while one exists.
///
/// The float is drawn INSIDE the buffer and changes without touching
/// anything the buffer's key can see: not the layer tree, not the surface's
/// tiles, not the overlay's. A key that missed it would freeze the canvas
/// for the whole drag — the same failure the tiled buffer shipped and had
/// to be reverted for, one input away.
///
/// ★Found by walking the painter's own body asking "what else can change",
/// which is the discipline those reverts bought
/// ([[cache-what-can-say-where-it-changed]]). This test is that walk, kept.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  BitmapSurfacePainter solidSurface(RgbaColor color) {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 4);
    tile = writeRgbaColorToBitmapTile(tile: tile, x: 0, y: 0, color: color);
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  testWidgets('moving a float repaints — the buffer is not kept under it', (
    tester,
  ) async {
    final float = SelectionFloatOverlay(
      SelectionFloatPaint(
        surface: solidSurface(RgbaColor(r: 255, g: 0, b: 0, a: 255)),
        surfaceOffset: CanvasPoint(x: 0, y: 0),
      ),
    );
    addTearDown(float.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 4,
              height: 4,
              child: CanvasLayerStackView(
                nodes: const [CanvasActiveLayerNode(opacity: 1)],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: solidSurface(
                  RgbaColor(r: 0, g: 0, b: 255, a: 255),
                ),
                floatOverlay: float,
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFF00FF00),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;

    Future<Uint8List> shot() async =>
        (await tester.runAsync(() => _rasterize(painter)))!;

    // 🚨WARM FIRST. The first paint is a cold miss and the second misses
    // again when the tile's decode lands, so a float moved before the third
    // would be picked up by a re-raster that was going to happen anyway —
    // and the test would pass with the guard REMOVED. Measured: it did.
    await shot();
    await shot();
    final before = await shot();

    // The drag: the float moves and NOTHING else does. No pump — a float
    // step reaches the canvas through the repaint Listenable, which is
    // exactly the moment a cache can swallow it.
    float.value = SelectionFloatPaint(
      surface: solidSurface(RgbaColor(r: 255, g: 0, b: 0, a: 255)),
      surfaceOffset: CanvasPoint(x: 2, y: 2),
    );
    final after = await shot();

    expect(
      after,
      isNot(equals(before)),
      reason: 'the float moved and the canvas did not — a kept buffer is '
          'showing where the selection used to be',
    );
  });
}

Future<Uint8List> _rasterize(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  const size = Size(4, 4);
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(4, 4);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}
