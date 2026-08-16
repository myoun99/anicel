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

/// #15 — THE 1PX BRIGHT LINE AT THE PAPER'S OUTER EDGE, ONLY BELOW ~30%.
///
/// Device observation (Windows, long-standing): a bright line rings the
/// canvas at zoom <= ~29% and is gone at >= ~32%, even when EVERY canvas
/// pixel holds opaque black ink — so the white cannot be uncovered paper
/// inside the canvas. What discriminates 29% from 32% is not a zoom
/// constant anywhere: it is the visible rect crossing the display
/// buffer's 8192 cap. Above the crossover the s=1 buffer composites
/// paper and ink JOINTLY at canvas resolution (both land on integral
/// canvas pixels, one raster) and the single blit resamples finished
/// pixels. Below it the SCALED buffer records at s < 1, where every
/// element is resampled separately: the paper's edge is analytic rect
/// coverage (~1 buffer px of ramp) while the ink's edge is a bilinear
/// window over canvas-resolution texels (~s buffer px, steeper) — two
/// rasterizations of the same geometric line that disagree in width and
/// phase, so the composite keeps paper white where the ink has already
/// thinned.
///
/// The fixture pins both sides of the crossover on one geometry: a
/// 2016x1266 canvas filled with opaque black exactly to the canvas edge
/// (the AA-off fill), a 2400px-wide view, pan chosen so the buffer's
/// origin lands on whole buffer pixels while the canvas's far edges land
/// at fractional ones (the phase where the bleed is strongest and the
/// blit cannot dilute it). Over a dark backdrop, ink pixels read 0 and
/// the backdrop 16 — ANY bright pixel is the bug.
void main() {
  const canvasSize = CanvasSize(width: 2016, height: 1266);
  final tileCache = BitmapTileImageCache.instance;

  BitmapSurface blackFilledSurface() {
    // The AA-off fill's bytes: every CANVAS pixel opaque black, tile
    // texels past the canvas edge transparent — the fill writes canvas
    // pixels, never tile extents, so the ink's edge is a CONTENT edge
    // interior to the flat projection's image.
    final tiles = <TileCoord, BitmapTile>{};
    for (var ty = 0; ty * 256 < canvasSize.height; ty += 1) {
      for (var tx = 0; tx * 256 < canvasSize.width; tx += 1) {
        final pixels = Uint8List(256 * 256 * 4);
        for (var y = 0; y < 256 && ty * 256 + y < canvasSize.height; y += 1) {
          for (var x = 0; x < 256 && tx * 256 + x < canvasSize.width; x += 1) {
            pixels[(y * 256 + x) * 4 + 3] = 255;
          }
        }
        final coord = TileCoord(x: tx, y: ty);
        tiles[coord] = BitmapTile(coord: coord, size: 256, pixels: pixels);
      }
    }
    return BitmapSurface(canvasSize: canvasSize, tileSize: 256, tiles: tiles);
  }

  Future<void> decodeAll(BitmapSurface surface) async {
    for (final tile in surface.tiles.values) {
      tileCache.ensureDecoded(tile);
    }
    while (surface.tiles.values.any((t) => tileCache.imageFor(t) == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<({CustomPainter painter, DisplayBufferCache cache})> pump(
    WidgetTester tester, {
    required BitmapSurface surface,
    required CanvasViewport viewport,
  }) async {
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 8,
              child: CanvasLayerStackView(
                nodes: const [CanvasActiveLayerNode(opacity: 1)],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: viewport,
                activeSurfacePainter: BitmapSurfacePainter(
                  surface: surface,
                  showTransparentBackground: false,
                ),
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFFFFFFFF),
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
    return (painter: painter, cache: cache);
  }

  /// The painter over the app's dark backdrop — the plane the white line
  /// is seen against on the device.
  Future<Uint8List> paintOverBackdrop(
    WidgetTester tester,
    CustomPainter painter,
    Size size,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF101010),
      );
      painter.paint(canvas, size);
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

  /// The bug's signature: with every canvas pixel opaque black over a
  /// 0xFF101010 backdrop, nothing legitimate on screen is brighter than
  /// the backdrop — a pixel with every channel >= 48 can only be paper
  /// white leaking at the edge.
  int brightPixels(Uint8List bytes) {
    var n = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] >= 48 && bytes[i + 1] >= 48 && bytes[i + 2] >= 48) {
        n += 1;
      }
    }
    return n;
  }

  /// Presence anchor: the ink really rendered (near-black pixels, darker
  /// than the 0x10 backdrop).
  int inkPixels(Uint8List bytes) {
    var n = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] <= 8 && bytes[i + 1] <= 8 && bytes[i + 2] <= 8) {
        n += 1;
      }
    }
    return n;
  }

  // Pan 1120/70 at dpr 1 survives the device-pixel snap unchanged and
  // makes the buffer origin land on whole buffer pixels (1120/0.28 = 4000,
  // 70/0.28 = 250, both integral), so the final blit is texel-exact and
  // cannot dilute the edge band — while the canvas's far edges land at
  // buffer 6016*0.28 = 1684.48 and 1516*0.28 = 424.48, the fractional
  // phase where the two edge rasterizations disagree the most.
  const screen = Size(2400, 500);
  final belowCrossover = CanvasViewport(zoom: 0.28, panX: 1120, panY: 70);
  final aboveCrossover = CanvasViewport(zoom: 0.33, panX: 1120, panY: 70);

  testWidgets('below the cap crossover an opaque-black canvas keeps its '
      'edge ink-dark — no paper white leaks around the rim (#15)',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final surface = blackFilledSurface();
    await tester.runAsync(() => decodeAll(surface));
    final rig = await pump(tester, surface: surface, viewport: belowCrossover);

    final bytes = await paintOverBackdrop(tester, rig.painter, screen);

    // Engagement first: 2400/0.28 = 8571 canvas px crosses the 8192 cap,
    // so this paint MUST have taken the scaled path — without this pin
    // the zero below could be the s=1 buffer passing by accident.
    expect(
      rig.cache.lastBufferScale,
      moreOrLessEquals(0.28),
      reason: 'the below-knee scaled buffer really composed this frame',
    );
    expect(
      inkPixels(bytes),
      greaterThan(100000),
      reason: 'presence first — the black fill actually rendered',
    );
    expect(
      brightPixels(bytes),
      0,
      reason: 'every canvas pixel is opaque black: any bright pixel is '
          'paper white leaking through the edge band (#15)',
    );
  });

  testWidgets('above the crossover the same geometry is clean — the s=1 '
      'buffer composites paper and ink jointly (#15 control)',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final surface = blackFilledSurface();
    await tester.runAsync(() => decodeAll(surface));
    final rig = await pump(tester, surface: surface, viewport: aboveCrossover);

    final bytes = await paintOverBackdrop(tester, rig.painter, screen);

    expect(
      rig.cache.lastBufferScale,
      isNull,
      reason: '2400/0.33 = 7273 canvas px fits the cap — the canvas-'
          'resolution buffer serves this side of the crossover',
    );
    expect(rig.cache.fullCount, greaterThan(0));
    expect(inkPixels(bytes), greaterThan(100000));
    expect(
      brightPixels(bytes),
      0,
      reason: 'the s=1 buffer must stay clean — it is the reference the '
          'device observation pinned at >= 32%',
    );
  });
}
