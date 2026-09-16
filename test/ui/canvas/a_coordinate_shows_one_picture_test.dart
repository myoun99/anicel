import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★A COORDINATE SHOWS ONE PICTURE, AND IT IS THE RESULT'S (유저 절대규칙
/// 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」). What a
/// coordinate shows is decided once (`_SurfacePaintPass._coordinate`),
/// level 0 draws it and every level above is made from it — so a live
/// stroke reaches a level buffer as the exact box mean of its result tiles,
/// and pen-up, which hands those very images to the committed tiles,
/// changes nothing on screen.
///
/// The fixture: a 32×32 cel with an opaque black column every four pixels,
/// every tile pictured; a live stroke of one-pixel black columns two pixels
/// to the right of them over the top-left 16×16, pre-blended by the real
/// rasterizer into overlay tiles. At 25% (level 2) each device pixel is a
/// 4×4 block: an untouched block holds one black column in four (191 over
/// white paper), a stroked block two (128). Nearest — what the stroke's
/// tiles used to be reduced by — reads 0 or 255 there, never 128.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 32, height: 32);
  final cache = BitmapTileImageCache.instance;
  const black = [0, 0, 0, 255];
  const clear = [0, 0, 0, 0];

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
      staleScope: BitmapTileImageCache.unfiled,
    );
    picture.dispose();
    return tile;
  }

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

  /// One-pixel black column dabs at x ≡ 2 (mod 4) over canvas 0..16 × 0..16.
  List<BrushDab> strokeDabs() {
    var sequence = 0;
    return [
      for (var x = 2; x < 16; x += 4)
        for (var y = 0; y < 16; y += 1)
          BrushDab(
            center: CanvasPoint(x: x + 0.5, y: y + 0.5),
            color: 0xFF000000,
            size: 1,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: sequence++,
          ),
    ];
  }

  Widget stackAt({
    required CanvasViewport viewport,
    required Size logicalSize,
    required BitmapSurfacePainter live,
    required LayerFrameImageCache images,
    DisplayBufferCache? buffers,
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
            debugBufferCache: buffers,
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

  int red(Uint8List bytes, int x, int y, int width) => bytes[(y * width + x) * 4];

  testWidgets('at 25% the live stroke is the exact mean of its result tiles, '
      'and pen-up — which hands those images to the committed tiles — '
      'changes not one byte on screen', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = LayerFrameImageCache(frameStore: BrushFrameStore());
    addTearDown(images.dispose);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final surface = columns();

    // The stroke, the way the interactive view makes one: the real
    // rasterizer's exact commit math, pre-blended against the cel into the
    // overlay's result tiles.
    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = surface
      ..blendMode = BrushBlendMode.color;
    addTearDown(overlay.dispose);
    final dabs = strokeDabs();
    await tester.runAsync(() async {
      final region = rasterizer.blendFrom(dabs, from: 0);
      overlay.dabs.addAll(dabs);
      overlay.updateRegion(source: rasterizer, region: region!);
      await overlay.waitForPendingDecodes();
    });
    expect(
      overlay.tileImages.keys.toSet(),
      {
        for (var ty = 0; ty < 2; ty += 1)
          for (var tx = 0; tx < 2; tx += 1) TileCoord(x: tx, y: ty),
      },
      reason: 'the stroke touched the top-left four tiles',
    );

    // 32×32 canvas px in an 8×8 view: one device pixel per 4×4 block.
    const logicalSize = Size(8, 8);
    final live = BitmapSurfacePainter(
      surface: surface,
      overlayModel: overlay,
      showTransparentBackground: false,
    );
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25),
        logicalSize: logicalSize,
        live: live,
        images: images,
        buffers: buffers,
      ),
    );
    await tester.pumpAndSettle();
    // Level tiles are made within a paint's ration; a second paint sees
    // the whole 4-block view made.
    await paintBytes(tester, painterOf(tester), logicalSize);
    final whileDrawing = await paintBytes(tester, painterOf(tester), logicalSize);
    expect(buffers.lastBufferLevel, 2);
    // The paper's outer level pixel is yielded (#15): read the interior.
    for (var y = 1; y < 7; y += 1) {
      for (var x = 1; x < 7; x += 1) {
        final stroked = x < 4 && y < 4;
        expect(
          red(whileDrawing, x, y, 8),
          inInclusiveRange(stroked ? 126 : 189, stroked ? 130 : 193),
          reason: '($x,$y) ${stroked ? 'under the stroke: two' : 'untouched: one'} '
              'black column in four — the block mean, not one texel of it',
        );
      }
    }

    // PEN-UP, the way commitStroke does it: promote the stroke's tiles,
    // hand each the overlay image that shows exactly its pixels, install
    // them, drop the overlay.
    final promoted = rasterizer.promoteStrokeTiles(
      base: surface,
      mode: BrushBlendMode.color,
      erase: false,
    );
    expect(promoted, hasLength(4));
    final placed = <PlacedTile>[];
    for (final entry in promoted) {
      final image = overlay.takeTileImageAt(
        entry.coord,
        revision: entry.revision,
      );
      expect(image, isNotNull, reason: 'every decode landed before pen-up');
      cache.adoptDecoded(
        (coord: entry.coord, tile: entry.tile),
        image!,
        staleScope: BitmapTileImageCache.unfiled,
      );
      placed.add((coord: entry.coord, tile: entry.tile));
    }
    final committed = surface.putMaterializedTiles(placed);
    overlay.reset();
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25),
        logicalSize: logicalSize,
        live: BitmapSurfacePainter(
          surface: committed,
          overlayModel: overlay,
          showTransparentBackground: false,
        ),
        images: images,
        buffers: buffers,
      ),
    );
    await tester.pumpAndSettle();
    await paintBytes(tester, painterOf(tester), logicalSize);
    final afterPenUp = await paintBytes(tester, painterOf(tester), logicalSize);
    expect(
      afterPenUp,
      whileDrawing,
      reason: 'the committed tiles show the very images the stroke showed: '
          'nothing on screen may change at pen-up',
    );
  });
}
