// BELOW THE KNEE, THE MISS PAINT IS THE WHOLE PICTURE — the same bytes the
// kept buffer serves on the next paint.
//
// 2026-09-04: _composeScaledBuffer had been routed through _bufferOf, whose
// pixel size is the RECT's (the s=1 law); below the knee the image is
// ceil(rect · s) a side, so the blit's source rect overshot the image and
// the miss frame landed shrunk in the corner. The kept branch kept the
// image's size, so every LATER paint was right — which is why the
// byte-checked knee test stayed green: it measured a hit. This one
// measures the miss, then the hit, and asks for the same bytes and for
// ink at the far right of both.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/composite_tree.dart';

void main() {
  // 12000 canvas px wide: past the 8192 cap at any test viewport, so every
  // paint here is below the knee by construction.
  const canvasSize = CanvasSize(width: 12000, height: 256);
  const screen = Size(300, 8);
  final tileCache = BitmapTileImageCache.instance;

  /// One solid red tile at the FAR RIGHT of the page (tile 45 of 46), so
  /// a blit that shrinks the picture into the corner has no red there.
  BitmapSurface farRightInk() {
    final pixels = Uint8List(256 * 256 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 255;
      pixels[i + 3] = 255;
    }
    final coord = TileCoord(x: 45, y: 0);
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 256,
      tiles: {coord: BitmapTile(coord: coord, size: 256, pixels: pixels)},
    );
  }

  Future<void> decodeAll(BitmapSurface surface) async {
    for (final tile in surface.tiles.values) {
      tileCache.ensureDecoded(tile);
    }
    while (surface.tiles.values.any((t) => tileCache.imageFor(t) == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<Uint8List> paintBytes(WidgetTester tester, CustomPainter painter) {
    return tester
        .runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), screen);
          final picture = recorder.endRecording();
          final image = picture.toImageSync(
            screen.width.round(),
            screen.height.round(),
          );
          picture.dispose();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        })
        .then((bytes) => bytes!);
  }

  /// Red pixels in the right tenth of the screen.
  int redAtTheFarRight(Uint8List bytes) {
    var red = 0;
    final width = screen.width.round();
    for (var y = 0; y < screen.height.round(); y += 1) {
      for (var x = width - width ~/ 10; x < width; x += 1) {
        final i = (y * width + x) * 4;
        if (bytes[i] > 200 && bytes[i + 1] < 60 && bytes[i + 2] < 60) {
          red += 1;
        }
      }
    }
    return red;
  }

  testWidgets('the miss paint below the knee is the whole picture — '
      'the same bytes the kept buffer serves next', (tester) async {
    final surface = farRightInk();
    await tester.runAsync(() => decodeAll(surface));
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: screen.width,
              height: screen.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasActiveLayerRow(opacity: 1),
                  ),
                ],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(zoom: 0.025),
                activeSurfacePainter: BitmapSurfacePainter(
                  surface: surface,
                  showTransparentBackground: false,
                ),
                paintPaper: true,
                paperBackground: ProjectBackground.defaultBackground,
                debugBufferCache: cache,
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
    expect(cache.lastBufferScale, isNotNull, reason: 'the knee path ran');
    expect(cache.lastBufferScale, lessThan(1));

    // The MISS: nothing kept, the scaled buffer composed and blitted.
    cache.invalidate();
    final fullsBefore = cache.fullCount;
    final miss = await paintBytes(tester, painter);
    expect(cache.fullCount, fullsBefore + 1, reason: 'that paint was a miss');
    // The HIT: the kept buffer, blitted with the image's own size.
    final hit = await paintBytes(tester, painter);
    expect(cache.fullCount, fullsBefore + 1, reason: 'that paint was a hit');

    expect(
      redAtTheFarRight(miss),
      greaterThan(0),
      reason: 'the far-right tile reaches the far right of the MISS frame',
    );
    expect(redAtTheFarRight(hit), greaterThan(0));
    expect(miss, equals(hit), reason: 'the miss and the hit draw one picture');
  });

  testWidgets('with NO cache at all the knee paint is still whole — the '
      'uncached return takes the same pixel size', (tester) async {
    final surface = farRightInk();
    await tester.runAsync(() => decodeAll(surface));
    // No debugBufferCache: every paint composes afresh and returns the
    // image the caller disposes. That return is a separate line from the
    // cached one, and it was the one the mutation campaign found unpinned.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: screen.width,
              height: screen.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasActiveLayerRow(opacity: 1),
                  ),
                ],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(zoom: 0.025),
                activeSurfacePainter: BitmapSurfacePainter(
                  surface: surface,
                  showTransparentBackground: false,
                ),
                paintPaper: true,
                paperBackground: ProjectBackground.defaultBackground,
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
    final bytes = await paintBytes(tester, painter);
    expect(
      redAtTheFarRight(bytes),
      greaterThan(0),
      reason:
          'the far-right tile reaches the far right with no cache in '
          'the picture — the uncached return is its own line',
    );
  });
}
