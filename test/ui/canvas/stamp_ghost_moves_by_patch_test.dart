// A STAMP GHOST THAT MOVES PATCHES THE BUFFER — THE OLD RECT AND THE NEW —
// INSTEAD OF COMPOSITING THE WHOLE CANVAS AGAIN. AND IT IS DRAWN ON EVERY
// ROUTE THE ACTIVE SLOT CAN TAKE.
//
// 🚨★★★F-130 measured it (2026-09-15, `cursor_at_os_speed_benchmark_test`,
// the stamp arm): 25 moves of the held piece, 25 FULL composes of the
// display buffer, 0 patches — 23ms a frame on the debug bar where the
// brush's own hover cost 8. The ghost was in the buffer's KEY (F-33: it
// rides the surface painter, so the buffer holds it) but not in its
// TOKENS, so a hover was a miss that could not say where it changed and
// fell through to the full raster. The tokens now carry the ghost, and a
// move is the union of where it was and where it is.
//
// F-33 is untouched on purpose: the ghost still rides the surface painter
// and composites as the layer — this only changes how much of the buffer
// is redrawn to move it. The pixels are pinned equal to a cold composite,
// including when the ghost crosses the edge of the active extent (F-85
// sizes the buffer by what the slot draws, ghost included, so that move
// changes the buffer's RECT and the carry has to repaint the ghost's two
// places as well as the exposed bands — adversarial review, 2026-09-15).
//
// And the two routes that replaced the walk — the flat projection below
// the knee, and the first-activation stand-in — never drew the ghost at
// all (the walk's `_paintStampPreview` was its only draw). Both draw it
// now, over their image, on their own route — the route is asserted, so
// a ghost cannot flip the slot to another draw and back (F-67's
// half-pixel shift).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

void main() {
  const side = 32;
  const canvasSize = CanvasSize(width: side, height: side);
  const size = Size(side * 1.0, side * 1.0);

  Future<ui.Image> decodedSquare() {
    final completer = Completer<ui.Image>();
    final rgba = Uint8List(4 * 4 * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 0xFF;
      rgba[i + 3] = 0xFF;
    }
    ui.decodeImageFromPixels(rgba, 4, 4, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  CutStampPreview ghostAt(Rect rect, ui.Image image) => CutStampPreview(
    piece: CutPiece(
      image: BrushStampImage(
        id: 'ghost',
        width: 4,
        height: 4,
        rgba: Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 255),
      ),
      originLeft: 0,
      originTop: 0,
    ),
    image: image,
    canvasRect: rect,
    opacity: 1,
    blendMode: BrushBlendMode.color,
  );

  Future<void> pumpView(
    WidgetTester tester,
    BitmapSurfacePainter painter,
    DisplayBufferCache cache, {
    double zoom = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
                ],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(zoom: zoom, panX: 0, panY: 0),
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

  /// The composite as the view paints it now, RGBA over a [side]² canvas.
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
    final recorder = ui.PictureRecorder();
    found.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = picture.toImageSync(side, side);
    } finally {
      picture.dispose();
    }
    try {
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * side + x) * 4 + 3];

  /// Paints, with real time between paints, until nothing is stored any
  /// more and no snapshot is still landing: the tile's decode has arrived
  /// and the real base describes the picture on screen. A move measured
  /// before that would see the decode's own dirty tile in its rect.
  Future<void> settle(WidgetTester tester, DisplayBufferCache cache) async {
    var quiet = 0;
    for (var round = 0; round < 20 && quiet < 2; round += 1) {
      final stores = cache.fullCount + cache.patchedCount;
      final promoted = cache.promotedCount;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await bytesNow(tester);
      quiet = cache.fullCount + cache.patchedCount == stores &&
              cache.promotedCount == promoted
          ? quiet + 1
          : 0;
    }
    expect(quiet, 2, reason: 'fixture: the buffer never settled');
  }

  /// The cold composite of [painter] as it stands: a fresh view, a fresh
  /// cache, nothing carried.
  Future<Uint8List> coldBytes(
    WidgetTester tester,
    BitmapSurfacePainter painter,
  ) async {
    final cold = DisplayBufferCache();
    addTearDown(cold.dispose);
    await pumpView(tester, painter, cold);
    return bytesNow(tester);
  }

  BitmapSurfacePainter tiledPainter(ValueNotifier<CutStampPreview?> preview) =>
      BitmapSurfacePainter(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 16,
          tiles: {TileCoord(x: 0, y: 0): BitmapTile.blank(size: 16)},
        ),
        showTransparentBackground: false,
        stampPreview: preview,
      );

  testWidgets('a move inside the active extent patches the buffer: no full '
      'compose, the dirty rect is the two ghost rects, the pixels are the '
      'cold composite\'s', (tester) async {
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    final image = (await tester.runAsync(decodedSquare))!;
    addTearDown(image.dispose);
    const was = Rect.fromLTWH(2, 2, 4, 4);
    const now = Rect.fromLTWH(10, 8, 4, 4);
    final preview = ValueNotifier<CutStampPreview?>(ghostAt(was, image));
    addTearDown(preview.dispose);
    final painter = tiledPainter(preview);
    await pumpView(tester, painter, cache);
    await settle(tester, cache);
    final before = await bytesNow(tester);
    expect(alphaAt(before, 3, 3), 0xFF, reason: 'fixture: the ghost is drawn where it was');
    final fullBefore = cache.fullCount;
    final patchedBefore = cache.patchedCount;

    // THE HOVER: the ghost moves, nothing else does.
    preview.value = ghostAt(now, image);
    await tester.pump();

    expect(cache.fullCount, fullBefore, reason: 'a moved ghost must not recomposite the whole buffer');
    expect(cache.patchedCount, patchedBefore + 1, reason: 'it is a patch');
    expect(
      cache.lastDirtyRect,
      was.expandToInclude(now).inflate(1),
      reason: 'the patch is where the ghost was and where it is, one pixel of hairline',
    );

    final patched = await bytesNow(tester);
    expect(alphaAt(patched, 3, 3), 0, reason: 'the old place is cleared');
    expect(alphaAt(patched, 11, 9), 0xFF, reason: 'the new place is inked');
    expect(patched, await coldBytes(tester, painter), reason: 'byte for byte the cold composite');
  });

  testWidgets('a ghost that crosses the edge of the active extent and comes '
      'back leaves no stale pixels — the buffer rect moves with it and the '
      'carry repaints both places', (tester) async {
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    final image = (await tester.runAsync(decodedSquare))!;
    addTearDown(image.dispose);
    // The tile covers (0,0)-(16,16); the ghost leaves it and returns.
    const inside = Rect.fromLTWH(2, 2, 4, 4);
    const outside = Rect.fromLTWH(22, 20, 4, 4);
    final preview = ValueNotifier<CutStampPreview?>(ghostAt(inside, image));
    addTearDown(preview.dispose);
    final painter = tiledPainter(preview);
    await pumpView(tester, painter, cache);
    await settle(tester, cache);

    for (final (step, rect, gone) in <(String, Rect, Rect)>[
      ('out', outside, inside),
      ('back', inside, outside),
      ('out again', outside, inside),
    ]) {
      preview.value = ghostAt(rect, image);
      await tester.pump();
      final shown = await bytesNow(tester);
      expect(
        alphaAt(shown, gone.left.toInt() + 1, gone.top.toInt() + 1),
        0,
        reason: '$step: the place the ghost left must read clear',
      );
      expect(
        alphaAt(shown, rect.left.toInt() + 1, rect.top.toInt() + 1),
        0xFF,
        reason: '$step: the place the ghost is must read inked',
      );
      expect(
        shown,
        await coldBytes(tester, painter),
        reason: '$step: byte for byte the cold composite',
      );
      // The next step must find the carried buffer, not a fresh view.
      await pumpView(tester, painter, cache);
      await settle(tester, cache);
    }
  });

  testWidgets('an EMPTY cel: the second step of a stroke patches — an empty '
      'snapshot is a base, not 「nothing kept」', (tester) async {
    // The stamp's usual target is an empty cel, and so is every drawing's
    // first stroke. The snapshot of an empty surface has no tiles; reading
    // that as a cold start (the old `kept.tiles.isEmpty`) refused the patch
    // on every step until the first commit put tiles there.
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: 16);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    final painter = BitmapSurfacePainter(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 16, tiles: const {}),
      overlayModel: overlay,
      showTransparentBackground: false,
    );
    BrushDab dabAt(double x, {int sequence = 0}) => BrushDab(
      center: CanvasPoint(x: x, y: 6),
      color: 0xFF000000,
      size: 3,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: sequence,
    );
    await pumpView(tester, painter, cache);
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(4)], from: 0);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 2, y: 4, width: 5, height: 5),
      );
      await overlay.waitForPendingDecodes();
    });
    await settle(tester, cache);
    final fullBefore = cache.fullCount;
    final patchedBefore = cache.patchedCount;
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(4), dabAt(8, sequence: 1)], from: 1);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 6, y: 4, width: 5, height: 5),
      );
      await overlay.waitForPendingDecodes();
    });
    await tester.pump();
    expect(cache.fullCount, fullBefore, reason: 'the second step must not raster the whole buffer');
    expect(cache.patchedCount, patchedBefore + 1, reason: 'it patches');
  });

  testWidgets('below the knee the flat projection draws the ghost over its '
      'image — the route stays flat, and the ghost is on screen', (
    tester,
  ) async {
    // The flat projection's fixture, as `the_layer_rides_the_draws_test`
    // found it has to be: the knee on, the view's ratio 1 (the gate is
    // `zoom · dpr < 1`), and the tile decoded in the singleton the
    // projection reads.
    MeasurementMode.kneeAtOne.value = true;
    addTearDown(() => MeasurementMode.kneeAtOne.value = false);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final tile = BitmapTile.blank(size: 16);
    await tester.runAsync(() async {
      BitmapTileImageCache.instance.ensureDecoded(
        (coord: TileCoord(x: 0, y: 0), tile: tile),
      );
      while (BitmapTileImageCache.instance.imageFor(tile) == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    final image = (await tester.runAsync(decodedSquare))!;
    addTearDown(image.dispose);
    final preview = ValueNotifier<CutStampPreview?>(null);
    addTearDown(preview.dispose);
    final painter = BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 16,
        tiles: {TileCoord(x: 0, y: 0): tile},
      ),
      showTransparentBackground: false,
      stampPreview: preview,
    );
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);

    debugActiveSlotDraw = null;
    await pumpView(tester, painter, cache, zoom: 0.63);
    expect(
      debugActiveSlotDraw,
      ActiveSlotDraw.flat,
      reason: 'fixture premise: without a ghost the knee path takes the flat',
    );

    preview.value = ghostAt(const Rect.fromLTWH(4, 4, 4, 4), image);
    debugActiveSlotDraw = null;
    await tester.pump();
    expect(
      debugActiveSlotDraw,
      ActiveSlotDraw.flat,
      reason: 'a ghost must not flip the slot to another draw (F-67)',
    );
    final shown = await bytesNow(tester);
    // At zoom 0.63 the ghost's (4,4)-(8,8) lands around (2.5,2.5)-(5,5).
    expect(alphaAt(shown, 3, 3), greaterThan(0), reason: 'the ghost is on screen');
  });

  testWidgets('on the first-activation swap frame the stand-in draws the '
      'ghost over the held image — the route stays the stand-in, and the '
      'ghost is on screen', (tester) async {
    // `first_activation_swap_frame_blank_test`'s fixture: a file-backed
    // cel shown as a cached image, then promoted with a tile cache that
    // knows none of its fresh tile objects — the frame the stand-in
    // exists for.
    const tileSize = 16;
    const tileCount = 4;
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
    );
    const celSize = CanvasSize(width: tileCount * tileSize, height: tileSize);
    final celBox = Size(celSize.width.toDouble(), celSize.height.toDouble());
    final tempDir = Directory.systemTemp.createTempSync('anicel-ghost-standin');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on Object catch (_) {}
    });
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(size: tileSize, pixels: pixels);
    }
    final surface = BitmapSurface(canvasSize: celSize, tileSize: tileSize, tiles: tiles);
    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final file = File('${tempDir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    final store = BrushFrameStore();
    store.restoreFromFile({
      key: AnicelCelFileRef(
        filePath: file.path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: celSize,
        tileSize: tileSize,
      ),
    });
    final imageCache = LayerFrameImageCache(frameStore: store);
    final prepared = await tester.runAsync(
      () => imageCache.prepare(
        key: key,
        canvasSize: celSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    expect(prepared, isNotNull, reason: 'fixture: the inactive route has an image');

    Future<void> pumpStack({
      required List<CompositeNode<CanvasStackRow>> nodes,
      BitmapSurfacePainter? activeSurfacePainter,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: celBox.width,
              height: celBox.height,
              child: CanvasLayerStackView(
                nodes: nodes,
                imageCache: imageCache,
                canvasSize: celSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: activeSurfacePainter,
                debugDisableBake: true,
              ),
            ),
          ),
        ),
      ),
    );

    Future<Uint8List> paintStack() async {
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
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder, Offset.zero & celBox), celBox);
      final picture = recorder.endRecording();
      try {
        return (await tester.runAsync(() async {
          final image = await picture.toImage(celSize.width, celSize.height);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            return data!.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        }))!;
      } finally {
        picture.dispose();
      }
    }

    List<int> rgbaAt(Uint8List px, int x, int y) {
      final o = (y * celSize.width + x) * 4;
      return [px[o], px[o + 1], px[o + 2], px[o + 3]];
    }

    await pumpStack(
      nodes: const [
        CompositeLeaf<CanvasStackRow>(
          CanvasLayerImageRequest(frameKey: key, opacity: 1),
        ),
      ],
    );
    await paintStack();

    // ACTIVATION with a ghost already in hand — the stamp tool was picked
    // before the layer.
    final image = (await tester.runAsync(decodedSquare))!;
    addTearDown(image.dispose);
    final preview = ValueNotifier<CutStampPreview?>(
      ghostAt(const Rect.fromLTWH(20, 4, 4, 4), image),
    );
    addTearDown(preview.dispose);
    final painter = BitmapSurfacePainter(
      surface: store.bakedSurfaceOrNull(key)!,
      showTransparentBackground: false,
      staleScope: 'ghost-stand-in-under-test',
      tileImageCache: BitmapTileImageCache(),
      stampPreview: preview,
    );
    await pumpStack(
      nodes: const [
        CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1, frameKey: key)),
      ],
      activeSurfacePainter: painter,
    );
    debugActiveSlotDraw = null;
    final swapFrame = await paintStack();
    expect(
      debugActiveSlotDraw,
      ActiveSlotDraw.standIn,
      reason: 'fixture premise: the swap frame draws the held image',
    );
    expect(rgbaAt(swapFrame, 8, 8), [0, 0, 255, 255], reason: 'the held artwork stands in');
    expect(rgbaAt(swapFrame, 22, 6), [255, 0, 0, 255], reason: 'the ghost is drawn over it');
  });
}
