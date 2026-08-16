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
import 'package:anicel/src/ui/canvas/active_layer_flat_projection.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/canvas/paper_background.dart';
import 'package:anicel/src/ui/canvas/static_composite_bake.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// ⓔ 5단계 — BELOW THE KNEE THE BUFFER RUNS AT SCREEN SCALE.
///
/// Past the old 8192 cap the stack used to fall to the direct walk — T21
/// territory, every layer resampled separately, the active one at nearest
/// beside its neighbours at bilinear. The knee path renders the SAME walk
/// into a screen-scale buffer where the active layer enters as ONE image
/// ([ActiveLayerFlatProjection]) under the same uniform filter.
void main() {
  // 12000 canvas px wide: at any test viewport this crosses the 8192 cap,
  // so every paint here is below the knee by construction. 256 TALL so
  // the ink is actually visible on the test screen — the first geometry
  // was 8px tall = 0.2 logical px at this zoom, and the byte oracle
  // compared two effectively-EMPTY images while the filter mutation
  // sailed through (measured: zero red pixels on both sides).
  const canvasSize = CanvasSize(width: 12000, height: 256);
  final tileCache = BitmapTileImageCache.instance;

  BitmapSurface inkedSurface() {
    // Two 256px tiles of 1px-wide vertical stripes. ⛔Anything
    // lower-frequency cannot anchor a sampling test at deep minification:
    // a bilinear 2×2 window only disagrees with nearest within one texel
    // of an edge, so even a hard 320px colour edge stayed green under
    // the none-mutation. Texel-scale stripes force the disagreement at
    // every output pixel: nearest snaps to a full or empty column,
    // bilinear averages the pair.
    final pixels = Uint8List(256 * 256 * 4);
    for (var y = 0; y < 256; y += 1) {
      for (var x = 0; x < 256; x += 2) {
        final i = (y * 256 + x) * 4;
        pixels[i] = 255;
        pixels[i + 3] = 255;
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 256,
      tiles: {
        for (var tx = 0; tx < 2; tx += 1)
          TileCoord(x: tx, y: 0): BitmapTile(
            coord: TileCoord(x: tx, y: 0),
            size: 256,
            pixels: pixels,
          ),
      },
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

  Future<
    ({CustomPainter painter, DisplayBufferCache cache, StaticCompositeBake bake})
  > pump(
    WidgetTester tester, {
    required BitmapSurface surface,
    ActiveStrokeOverlayModel? overlay,
    CanvasViewport? viewport,
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
                viewport: viewport ?? CanvasViewport(zoom: 0.025),
                activeSurfacePainter: BitmapSurfacePainter(
                  surface: surface,
                  overlayModel: overlay,
                  showTransparentBackground: false,
                ),
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFF00FF00),
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
    final bake =
        // ignore: avoid_dynamic_calls
        (tester.state(find.byType(CanvasLayerStackView)) as dynamic).debugBake
            as StaticCompositeBake;
    return (painter: painter, cache: cache, bake: bake);
  }

  Future<Uint8List> paintBytes(
    WidgetTester tester,
    CustomPainter painter,
    Size size,
  ) async {
    return tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        size.width.round(),
        size.height.round(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }).then((bytes) => bytes!);
  }

  double expectedScale(double zoom, double dpr, Rect rect) {
    var s = zoom * dpr;
    if (s >= 1) s = 1;
    final longSide = rect.width > rect.height ? rect.width : rect.height;
    if (longSide * s > 8192) s = 8192 / longSide;
    return s;
  }

  testWidgets('below the knee the buffer runs at screen scale and is kept',
      (tester) async {
    final surface = inkedSurface();
    await tester.runAsync(() => decodeAll(surface));
    final rig = await pump(tester, surface: surface);

    // The pump itself paints (one full per BUILD — the tree signature is
    // identity-based, same as the s=1 path). What this test owns is the
    // delta: paints without a rebuild must HIT the kept scaled buffer.
    final fullsAfterPump = rig.cache.fullCount;
    expect(fullsAfterPump, greaterThan(0), reason: 'the knee path composed');
    expect(
      rig.cache.lastBufferScale,
      isNotNull,
      reason: 'the scaled path really ran — a knee path that silently '
          'stops running looks exactly like one that works',
    );
    expect(rig.cache.lastBufferScale, lessThan(1));

    await paintBytes(tester, rig.painter, const Size(300, 8));
    await paintBytes(tester, rig.painter, const Size(300, 8));
    expect(
      rig.cache.fullCount,
      fullsAfterPump,
      reason: 'nothing moved — the kept screen-scale buffer serves every '
          'later paint',
    );
  });

  testWidgets('the knee path draws the flat active image under the '
      'uniform filter — byte-checked against an independent reference',
      (tester) async {
    final surface = inkedSurface();
    await tester.runAsync(() => decodeAll(surface));
    final rig = await pump(tester, surface: surface);
    const screen = Size(300, 8);
    final got = await paintBytes(tester, rig.painter, screen);
    expect(
      rig.cache.lastBufferScale,
      isNotNull,
      reason: 'engagement first — without it the equality below compares '
          'the WALK against the reference and passes by accident',
    );

    // The reference builds the same two-stage picture with nothing but
    // primitives: paper + the flat at LOW into a scale-s recording, then
    // one blit under the viewport transform. Byte equality here pins the
    // scale arithmetic AND the uniform filter — an active layer drawn at
    // nearest inside the buffer diverges at the ink's hard edge.
    final reference = await tester.runAsync(() async {
      const zoom = 0.025;
      final visible = Rect.fromLTWH(0, 0, 300 / zoom, 8 / zoom);
      final pasteboard = Rect.fromLTRB(
        -canvasSize.width.toDouble(),
        -canvasSize.height.toDouble(),
        canvasSize.width * 2.0,
        canvasSize.height * 2.0,
      );
      final bounds = pasteboard.intersect(visible);
      final rect = Rect.fromLTRB(
        bounds.left.floorToDouble(),
        bounds.top.floorToDouble(),
        bounds.right.ceilToDouble(),
        bounds.bottom.ceilToDouble(),
      );
      final s = expectedScale(zoom, tester.view.devicePixelRatio, rect);
      final flat = ActiveLayerFlatProjection.buildOrNull(
        surface: surface,
        tileImages: tileCache,
      )!;
      final recorder = ui.PictureRecorder();
      final into = Canvas(recorder);
      into.scale(s);
      into.translate(-rect.left, -rect.top);
      paintProjectPaper(
        into,
        // #15 — the scaled recording insets the paper by ONE BUFFER PIXEL
        // (1/s canvas px): separately-resampled paper and ink edges
        // disagree at fractional phases, and the inset keeps the plate
        // under the ink's solid region. The reference carries the same
        // law or the byte equality would pin its absence.
        Rect.fromLTWH(
          0,
          0,
          canvasSize.width.toDouble(),
          canvasSize.height.toDouble(),
        ).deflate(1 / s),
        const ProjectBackground.color(0xFF00FF00),
      );
      into.drawImageRect(
        flat.image,
        Rect.fromLTWH(
          0,
          0,
          flat.image.width.toDouble(),
          flat.image.height.toDouble(),
        ),
        flat.worldRect,
        Paint()..filterQuality = ui.FilterQuality.low,
      );
      final picture = recorder.endRecording();
      final buffer = picture.toImageSync(
        (rect.width * s).ceil(),
        (rect.height * s).ceil(),
      );
      picture.dispose();
      flat.image.dispose();

      final screenRecorder = ui.PictureRecorder();
      final screenCanvas = Canvas(screenRecorder);
      screenCanvas.save();
      screenCanvas.clipRect(Offset.zero & screen);
      screenCanvas.scale(zoom);
      screenCanvas.drawImageRect(
        buffer,
        Rect.fromLTWH(
          0,
          0,
          buffer.width.toDouble(),
          buffer.height.toDouble(),
        ),
        rect,
        Paint()..filterQuality = ui.FilterQuality.low,
      );
      screenCanvas.restore();
      final screenPicture = screenRecorder.endRecording();
      final screenImage = screenPicture.toImageSync(
        screen.width.round(),
        screen.height.round(),
      );
      screenPicture.dispose();
      buffer.dispose();
      final data = await screenImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      screenImage.dispose();
      return data!.buffer.asUint8List();
    });

    int redPixels(Uint8List bytes) {
      var n = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] > 32) n += 1;
      }
      return n;
    }

    expect(
      redPixels(got),
      greaterThan(0),
      reason: 'presence first — an equality between two empty images is '
          'how this test passed vacuously in its first geometry',
    );
    expect(got, reference);
  });

  testWidgets('nothing on screen, nothing painted — the empty viewport '
      'stops being a 25x pasteboard request', (tester) async {
    final surface = inkedSurface();
    await tester.runAsync(() => decodeAll(surface));
    // Panned a full pasteboard away: the visible rect misses everything.
    final rig = await pump(
      tester,
      surface: surface,
      viewport: CanvasViewport(zoom: 0.025, panX: -3000000),
    );

    final bytes = await paintBytes(tester, rig.painter, const Size(300, 8));
    expect(bytes.every((byte) => byte == 0), isTrue,
        reason: 'nothing intersects the screen');
    expect(rig.cache.fullCount, 0, reason: 'no buffer for no pixels');
  });

  testWidgets('a collapsed panel composes nothing — the degenerate view '
      'stops being a 25x pasteboard request', (tester) async {
    final surface = inkedSurface();
    await tester.runAsync(() => decodeAll(surface));
    final rig = await pump(tester, surface: surface);
    final base = rig.cache.fullCount;

    // The collapsed panel: paint at zero size. The old fallback swapped
    // an empty visible rect for the WHOLE pasteboard and composed it —
    // the largest request this painter can make, for pixels nobody sees.
    final recorder = ui.PictureRecorder();
    rig.painter.paint(Canvas(recorder), Size.zero);
    recorder.endRecording().dispose();

    expect(
      rig.cache.fullCount,
      base,
      reason: 'nothing on screen, nothing composed — the intersection is '
          'the one law for both ways off-screen happens',
    );
  });

  testWidgets('a DPR move re-rasters instead of stretching the old image — '
      'the resolved scale is in the key (구멍 ②)', (tester) async {
    final surface = inkedSurface();
    await tester.runAsync(() => decodeAll(surface));
    final rig = await pump(tester, surface: surface);
    await paintBytes(tester, rig.painter, const Size(300, 8));
    final fullsBefore = rig.cache.fullCount;
    final scaleBefore = rig.cache.lastBufferScale;

    // The monitor move: same widget, same viewport, a different device.
    // MediaQuery carries it into a rebuild, and the fresh painter must
    // re-raster at the new s instead of serving the old image.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(
      rig.cache.fullCount,
      greaterThan(fullsBefore),
      reason: 'a DPR move must re-raster — the resolved scale rides both '
          'the painter gate and the buffer key',
    );
    expect(rig.cache.lastBufferScale, isNot(scaleBefore));
  });

  testWidgets('the projection\'s refusal keeps the walk', (tester) async {
    final surface = inkedSurface();
    await tester.runAsync(() => decodeAll(surface));
    final overlay = ActiveStrokeOverlayModel(tileSize: 256);
    addTearDown(overlay.dispose);
    overlay.preBlendBase = surface;
    // Settling is one of the per-coordinate arbitration windows a single
    // image cannot express — the projection answers null, the knee path
    // steps aside, the walk draws.
    overlay.settling = true;
    overlay.markStandIn(TileCoord(x: 0, y: 0));

    final rig = await pump(tester, surface: surface, overlay: overlay);
    await paintBytes(tester, rig.painter, const Size(300, 8));

    expect(rig.cache.lastBufferScale, isNull);
    expect(rig.cache.fullCount, 0);
  });

  group('ⓔ 6단계 A/B — MeasurementMode.kneeAtOne', () {
    // Zoom 0.1 on the 12000px canvas: the visible rect is ~3000 canvas px
    // — WITHIN the 8192 cap, so without the toggle this view takes the
    // canvas-resolution buffer. s = 0.1 · dpr 3.0 = 0.3 < 1, so with the
    // knee at 1 it belongs to the screen-scale path.
    final withinCap = CanvasViewport(zoom: 0.1);

    testWidgets('OFF (default) is byte-for-byte today: the within-cap '
        'view takes the canvas-res buffer, never the scaled path',
        (tester) async {
      final surface = inkedSurface();
      await tester.runAsync(() => decodeAll(surface));
      final rig = await pump(tester, surface: surface, viewport: withinCap);
      await paintBytes(tester, rig.painter, const Size(300, 8));

      expect(rig.cache.fullCount, greaterThan(0),
          reason: 'the canvas-res buffer composed');
      expect(
        rig.cache.lastBufferScale,
        isNull,
        reason: 'with the switch off the scaled path must never run '
            'within the cap — OFF means the build behaves as before '
            'stage 6 existed',
      );
    });

    testWidgets('ON: the same view composes at screen scale', (tester) async {
      MeasurementMode.kneeAtOne.value = true;
      addTearDown(MeasurementMode.reset);
      final surface = inkedSurface();
      await tester.runAsync(() => decodeAll(surface));
      final rig = await pump(tester, surface: surface, viewport: withinCap);
      await paintBytes(tester, rig.painter, const Size(300, 8));

      expect(
        rig.cache.lastBufferScale,
        moreOrLessEquals(0.1 * tester.view.devicePixelRatio),
        reason: 'within the cap nothing shrinks s further — the scale is '
            'exactly zoom·dpr',
      );
    });

    testWidgets('ON at s >= 1: the gate never fires — above 100% is the '
        'same code and the same bytes', (tester) async {
      MeasurementMode.kneeAtOne.value = true;
      addTearDown(MeasurementMode.reset);
      final surface = inkedSurface();
      await tester.runAsync(() => decodeAll(surface));
      // zoom 0.5 · dpr 3.0 = s 1.5.
      final rig = await pump(
        tester,
        surface: surface,
        viewport: CanvasViewport(zoom: 0.5),
      );
      await paintBytes(tester, rig.painter, const Size(300, 8));

      expect(rig.cache.fullCount, greaterThan(0));
      expect(
        rig.cache.lastBufferScale,
        isNull,
        reason: 'the above-100% byte-invariance check-point is structural: '
            'the gate must not run the scaled path when the artwork has '
            'no more pixels than the screen',
      );
    });

    testWidgets('ON + a refusal WITHIN the cap falls through to the '
        'canvas-res buffer, not the walk', (tester) async {
      MeasurementMode.kneeAtOne.value = true;
      addTearDown(MeasurementMode.reset);
      final surface = inkedSurface();
      await tester.runAsync(() => decodeAll(surface));
      // Rotation is the scaled buffer's own refusal (the blit could not
      // be 1:1) — but inside the cap the canvas-res buffer handles any
      // viewport transform, so stepping all the way down to the walk
      // would pay T21 for nothing.
      final rig = await pump(
        tester,
        surface: surface,
        viewport: CanvasViewport(zoom: 0.1, rotationDegrees: 30),
      );
      await paintBytes(tester, rig.painter, const Size(300, 8));

      expect(rig.cache.lastBufferScale, isNull,
          reason: 'the scaled path refused (rotation)');
      expect(
        rig.cache.fullCount,
        greaterThan(0),
        reason: 'the refusal must land on the canvas-res buffer — a walk '
            'stores nothing, and a zero here means the A/B quietly '
            'degrades rotated views instead of measuring them',
      );
    });

    testWidgets('flipping the switch repaints the SAME view — the A/B is '
        'two readings of one picture', (tester) async {
      final surface = inkedSurface();
      await tester.runAsync(() => decodeAll(surface));
      final rig = await pump(tester, surface: surface, viewport: withinCap);
      expect(rig.cache.lastBufferScale, isNull, reason: 'fixture: OFF');

      MeasurementMode.kneeAtOne.value = true;
      addTearDown(MeasurementMode.reset);
      await tester.pump();

      expect(
        rig.cache.lastBufferScale,
        isNotNull,
        reason: 'the switch rides the painter\'s repaint merge — without '
            'it the flip does nothing until something else moves',
      );
    });
  });
}
