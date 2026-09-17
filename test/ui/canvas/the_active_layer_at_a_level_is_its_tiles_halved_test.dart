import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★THE ACTIVE LAYER AT A LEVEL IS ITS TILES HALVED (render round 4c,
/// 2026-09-16). Below 100% the display buffer is a level, and until 4c the
/// active layer's tiles were the one thing in it still reduced by nearest
/// under the recorder's scale. Now the committed tiles reach a level
/// buffer as LEVEL TILES ([TilePyramid]) — each an exact box mean of its
/// block, drawn 1:1 in the buffer's pixels — so the layer being drawn on
/// and the layers around it are the same picture at every zoom.
///
/// The fixture is the cel from `below_100_the_buffer_is_a_level_test` as
/// the ACTIVE layer: 64×32, an opaque black column every four pixels, every
/// tile with its picture already in the cache. At 25% each device pixel is
/// a 4×4 block holding one column — a quarter ink over white paper reads
/// 191; nearest reads 0 or 255.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 64, height: 32);
  final cache = BitmapTileImageCache.instance;

  /// A tile of [size] whose pixels are [rgbaAt], with its picture drawn
  /// the same way and given to the cache as a landed decode.
  BitmapTile pictured(
    TileCoord coord,
    int size,
    List<int> Function(int x, int y) rgbaAt,
  ) {
    final pixels = Uint8List(size * size * 4);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (var y = 0; y < size; y += 1) {
      for (var x = 0; x < size; x += 1) {
        final rgba = rgbaAt(x, y);
        pixels.setRange((y * size + x) * 4, (y * size + x) * 4 + 4, rgba);
        if (rgba[3] != 0) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x * 1.0, y * 1.0, 1, 1),
            ui.Paint()
              ..color = ui.Color.fromARGB(rgba[3], rgba[0], rgba[1], rgba[2]),
          );
        }
      }
    }
    final tile = BitmapTile(size: size, pixels: pixels);
    final picture = recorder.endRecording();
    cache.adoptDecoded(
      (coord: coord, tile: tile),
      picture.toImageSync(size, size),
    );
    picture.dispose();
    return tile;
  }

  const black = [0, 0, 0, 255];
  const clear = [0, 0, 0, 0];

  /// Every tile of the cel: a black column at every fourth canvas x.
  BitmapSurface columns() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty * tileSize < canvasSize.height; ty += 1)
        for (var tx = 0; tx * tileSize < canvasSize.width; tx += 1)
          TileCoord(x: tx, y: ty): pictured(
            TileCoord(x: tx, y: ty),
            tileSize,
            (x, y) => (tx * tileSize + x) % 4 == 0 ? black : clear,
          ),
    },
  );

  Widget stackAt({
    required CanvasViewport viewport,
    required Size logicalSize,
    required BitmapSurfacePainter live,
    required LayerFrameImageCache images,
    DisplayBufferCache? cache,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: CanvasLayerStackView(
            nodes: const [
              CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
            ],
            imageCache: images,
            canvasSize: canvasSize,
            viewport: viewport,
            activeSurfacePainter: live,
            paintPaper: true,
            paperBackground: ProjectBackground.defaultBackground,
            debugBufferCache: cache,
          ),
        ),
      ),
    ),
  );

  CustomPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(CanvasLayerStackView),
          matching: find.byType(CustomPaint),
        ),
      )
      .where((paint) => paint.painter != null)
      .first
      .painter!;

  Future<Uint8List> paintBytes(
    WidgetTester tester,
    CustomPainter painter,
    Size size,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder, Offset.zero & size), size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        size.width.round(),
        size.height.round(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  testWidgets('at 25% every pixel of the active layer is the mean of its '
      '4×4 block — a level tile, not nearest', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = LayerFrameImageCache(frameStore: BrushFrameStore());
    addTearDown(images.dispose);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final live = BitmapSurfacePainter(
      surface: columns(),
      showTransparentBackground: false,
    );
    // The cel's interior (canvas x 16..48 × y 8..24) in an 8×4 view: one
    // device pixel per 4×4 block, away from the paper's yielded edge.
    const logicalSize = Size(8, 4);
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25, panX: -4, panY: -2),
        logicalSize: logicalSize,
        live: live,
        images: images,
        cache: buffers,
      ),
    );
    await tester.pumpAndSettle();
    // Level tiles are made within a paint's ration; two paints see the
    // whole 8-block view made.
    await paintBytes(tester, painterOf(tester), logicalSize);
    final bytes = await paintBytes(tester, painterOf(tester), logicalSize);
    expect(buffers.lastBufferLevel, 2);
    for (var i = 0; i < bytes.length; i += 4) {
      expect(bytes[i + 3], 255, reason: 'pixel ${i ~/ 4} is opaque');
      expect(
        bytes[i],
        inInclusiveRange(189, 193),
        reason: 'pixel ${i ~/ 4}: one column in four is ink, so the level '
            'tile reads 191 — 0 or 255 is a tile drawn by nearest under '
            'the recorder\'s scale',
      );
    }
  });
}
