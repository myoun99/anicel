import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨ONE RESOLUTION AT EVERY ZOOM — the editing canvas composites the way
/// playback, the camera and the export do, and keeps doing it however far
/// you zoom out.
///
/// The buffers used to be bounded by `pasteboard ∩ visibleRect`. Zoom out
/// far enough and that rect spans the whole pasteboard — 5×5 canvases,
/// 11700×8270 on a 2340×1654 page — which exceeds the buffer cap and drops
/// the paint onto the SCREEN-resolution fallback. That fallback is the one
/// place the editing canvas stops matching the other routes.
///
/// Bounding by CONTENT keeps the page at 2340×1654, which never reaches the
/// cap. This pins that as a NUMBER rather than an argument.
void main() {
  // 🧪MEASURED, not assumed: the pasteboard is the canvas grown by ONE canvas
  // per side, so it is 3× the page per axis. A 2340×1654 page tops out at
  // 7020×4962 — UNDER the 8192 cap, which is why a first version of this
  // test could not tell the two bounds apart. 3000×2000 crosses it: its
  // pasteboard is 9000×6000.
  const canvasSize = CanvasSize(width: 3000, height: 2000);

  BitmapSurfacePainter inkedPage() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256);
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: 4,
      y: 4,
      color: RgbaColor(r: 0, g: 0, b: 255, a: 255),
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  Future<void> paintAt(
    WidgetTester tester,
    double zoom, {
    double panX = 0,
    double panY = 0,
    bool inFolder = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey<String>('zoom-$zoom'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: CanvasLayerStackView(
                nodes: inFolder
                    ? [
                        const CanvasLayerGroupNode(
                          children: [CanvasActiveLayerNode(opacity: 1)],
                          opacity: 1,
                          blendMode: LayerBlendMode.multiply,
                        ),
                      ]
                    : const [CanvasActiveLayerNode(opacity: 1)],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(zoom: zoom, panX: panX, panY: panY),
                activeSurfacePainter: inkedPage(),
                paintPaper: true,
                paperBackground: ProjectBackground.defaultBackground,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 🚨PAINT EXPLICITLY. A widget test's pump builds and lays out, and the
    // counter this asserts on only moves inside CustomPainter.paint — a
    // pump alone left it at zero and the mutation went unnoticed.
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty, reason: 'the stack must mount a painter');
    const size = Size(400, 300);
    final recorder = PictureRecorder();
    painted.first.painter!.paint(Canvas(recorder, Offset.zero & size), size);
    recorder.endRecording().dispose();
  }

  testWidgets('zooming out never drops the composite to screen resolution', (
    tester,
  ) async {
    // ⛔The counter is global; a stale value from another test would make
    // this one report on work it never did.
    debugCappedFallbacks = 0;

    // Fit-to-page and well past it — at 0.02 the 400×300 window pulls back a
    // canvas-space rect far wider than the page, and the OLD bounds handed
    // the whole pasteboard to the buffer.
    await paintAt(tester, 1.0);
    await paintAt(tester, 0.2);
    // 🚨THE CASE THAT USED TO FALL THROUGH. Zoomed out to 2% AND panned so
    // the whole 5×5 pasteboard sits inside the window — that is when the
    // old bounds handed the buffer an 11700×8270 rect, past the cap, and
    // the paint dropped to screen resolution. Without the pan the visible
    // rect only ever caught the positive quadrant and never reached it.
    await paintAt(tester, 0.02, panX: 200, panY: 150);

    expect(
      debugCappedFallbacks,
      0,
      reason: 'a 3000×2000 page bounds to itself, not to its 9000×6000 '
          'pasteboard, so no zoom reaches the cap and falls to screen resolution',
    );
  });

  testWidgets('a folder buffer stays inside the composite that holds it', (
    tester,
  ) async {
    debugCappedFallbacks = 0;
    // ⛔Bounded by the VIEW, a folder at this zoom asked for the whole
    // pasteboard — 9× the page — inside a buffer that is only the page.
    // The containment assert in the paint is what catches that; this scene
    // is what makes it run.
    await paintAt(tester, 0.02, panX: 200, panY: 150, inFolder: true);
    expect(debugCappedFallbacks, 0);
  });
}
