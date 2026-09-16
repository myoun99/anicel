import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★BELOW 100% THE BUFFER IS A LEVEL (render round, 안 1 「선명」,
/// 2026-09-16). One composite image, one blit, at every zoom — and below
/// 100% that image is the artwork halved until the blit reduces it by
/// (0.5, 1]: the buffer is the screen's size, not the visible canvas's,
/// and every level pixel is the exact mean of its block.
///
/// The fixture is a 64×32 cel with an opaque black column every four
/// pixels, shown as a cached (non-active) layer. At 25% each device pixel
/// is a 4×4 block holding exactly one black column — a quarter ink — so the
/// level buffer reads 191 everywhere over white paper. The two ways of
/// getting it wrong read differently: a canvas-resolution buffer reduced by
/// one bilinear step samples a 2×2 window of each 4×4 block (255 or 128,
/// by phase), and nearest reads 0 or 255.
void main() {
  const canvasSize = CanvasSize(width: 64, height: 32);
  const projectId = ProjectId('project');
  const trackId = TrackId('track');
  const cutId = CutId('cut');
  const layerId = LayerId('layer');
  const frameId = FrameId('frame');
  const frameKey = BrushFrameKey(
    projectId: projectId,
    trackId: trackId,
    cutId: cutId,
    layerId: layerId,
    frameId: frameId,
  );

  /// A black column at every fourth x, one pixel wide, the cel's height.
  BrushFrameStore storeWithColumns() {
    final store = BrushFrameStore();
    var sequence = 0;
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 8,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        for (var x = 0; x < canvasSize.width; x += 4)
          for (var y = 0; y < canvasSize.height; y += 1)
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
      ],
    );
    return store;
  }

  /// The cel's image made at [quality] BEFORE the stack mounts, so its
  /// first paint already holds it — the way `a_pan_carries_what_it_had`
  /// warms its cache.
  Future<LayerFrameImageCache> warmImages(
    WidgetTester tester,
    BrushFrameStore store,
    PlaybackQuality quality,
  ) async {
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    await tester.runAsync(
      () => images.prepare(
        key: frameKey,
        canvasSize: canvasSize,
        quality: quality,
        sourceEffects: const [],
      ),
    );
    return images;
  }

  /// An active layer with one blank tile — the carry measures where the
  /// live surface changed, and there has to be one to measure. Its picture
  /// is given to the cache up front: a decode landing later would bump the
  /// cache's revision and recompose the buffer whole, which is not what
  /// this measures.
  BitmapSurfacePainter blankLive() {
    final tile = BitmapTile.blank(size: 8);
    final coord = TileCoord(x: 0, y: 0);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(8, 8);
    picture.dispose();
    BitmapTileImageCache.instance.adoptDecoded(
      (coord: coord, tile: tile),
      image,
      staleScope: BitmapTileImageCache.unfiled,
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  Widget stackAt({
    required CanvasViewport viewport,
    required LayerFrameImageCache images,
    required Size logicalSize,
    DisplayBufferCache? cache,
    BitmapSurfacePainter? live,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: CanvasLayerStackView(
            nodes: [
              const CompositeLeaf<CanvasStackRow>(
                CanvasLayerImageRequest(frameKey: frameKey, opacity: 1),
              ),
              if (live != null)
                const CompositeLeaf<CanvasStackRow>(
                  CanvasActiveLayerRow(opacity: 1),
                ),
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

  testWidgets('at 25% the buffer is a level-2 image — the screen\'s size, '
      'not the canvas\'s — and every pixel is the mean of its 4×4 block',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = await warmImages(
      tester,
      storeWithColumns(),
      PlaybackQuality.quarter,
    );
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    // Canvas x 16..48 × y 8..24 in an 8×4 logical view: one device pixel
    // per 4×4 block, and the cel's INTERIOR — inside a level buffer the
    // paper yields its outer level pixel (#15, `_paintPaperInto`), so the
    // edge ring is not paper and is not this test's question.
    const logicalSize = Size(8, 4);
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25, panX: -4, panY: -2),
        images: images,
        logicalSize: logicalSize,
        cache: cache,
      ),
    );
    await tester.pumpAndSettle();
    final bytes = await paintBytes(tester, painterOf(tester), logicalSize);

    expect(cache.lastBufferLevel, 2, reason: '25% is level 2');
    expect(
      cache.heldBytes,
      lessThanOrEqualTo(2 * 8 * 4 * 4),
      reason: 'the buffer (and its snapshot) is 8×4 level pixels, not the '
          '32×16 canvas pixels it shows: ${cache.heldBytes} bytes held',
    );
    expect(cache.fullCount, greaterThan(0));
    for (var i = 0; i < bytes.length; i += 4) {
      expect(bytes[i + 3], 255, reason: 'pixel ${i ~/ 4} is opaque');
      expect(
        bytes[i],
        inInclusiveRange(189, 193),
        reason: 'pixel ${i ~/ 4}: a quarter of each 4×4 block is ink, so the '
            'level reads 191 — 255 or 128 is one bilinear step over the '
            'canvas-resolution picture, 0/255 is nearest',
      );
    }
  });

  testWidgets('the level image is asked of the cache at the level\'s '
      'quality — quarter at 25%, half at 40%, full at 60%', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (zoom, quality) in [
      (0.25, PlaybackQuality.quarter),
      (0.4, PlaybackQuality.half),
      (0.6, PlaybackQuality.full),
    ]) {
      final store = storeWithColumns();
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      await tester.pumpWidget(
        stackAt(
          viewport: CanvasViewport(zoom: zoom),
          images: images,
          logicalSize: const Size(16, 8),
        ),
      );
      // The image is made off the frame ([LayerFrameImageCache.prepare]
      // awaits its raster): let real time pass for the engine and test
      // time for the frame until it lands.
      LayerFrameImage? made;
      for (var i = 0; i < 60 && made == null; i += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        made = images.validImageOrNull(
          frameKey,
          quality,
          canvasSize: canvasSize,
          sourceEffects: const [],
        );
      }
      await tester.pumpAndSettle();
      expect(
        made,
        isNotNull,
        reason: 'zoom $zoom: the stack must have prepared the $quality image',
      );
      for (final other in PlaybackQuality.values) {
        if (other == quality) {
          continue;
        }
        expect(
          images.validImageOrNull(
            frameKey,
            other,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          isNull,
          reason: 'zoom $zoom: only the level\'s quality is prepared, not '
              '$other',
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a pan by whole level pixels carries the kept level buffer '
      'instead of composing it whole', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = await warmImages(
      tester,
      storeWithColumns(),
      PlaybackQuality.quarter,
    );
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    final live = blankLive();
    // ⛔SMALL, so a pan actually moves the extent: 32×32 canvas px in an
    // 8×8 logical view at level 2 — half the cel.
    const logicalSize = Size(8, 8);
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25),
        images: images,
        logicalSize: logicalSize,
        cache: cache,
        live: live,
      ),
    );
    await tester.pumpAndSettle();
    // The snapshot the next miss measures from lands off the frame
    // ([DisplayBufferCache.promote]).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(cache.lastBufferLevel, 2);
    expect(cache.fullCount, 1, reason: 'fixture: one cold compose');
    expect(cache.scrolledCount, 0);

    // One logical pixel = one level pixel = four canvas pixels: the view
    // now holds canvas x 4..36, overlapping the kept 0..32 by whole level
    // pixels.
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25, panX: -1),
        images: images,
        logicalSize: logicalSize,
        cache: cache,
        live: live,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      cache.scrolledCount,
      greaterThan(0),
      reason: 'the overlap is offset by whole level pixels and is carried',
    );
    // 🚨THE COUNTER SAYS THE CARRY RAN; THE AREA SAYS IT SAVED SOMETHING
    // ([DisplayBufferCache.lastComposedArea]) — a carry that blits the
    // overlap and composites the whole rect anyway is invisible to every
    // counter. The view is 32×32 canvas px; the pan exposed a band four
    // canvas px (one level pixel) wide.
    expect(
      cache.lastComposedArea,
      isNotNull,
      reason: 'the carry composited the exposed band',
    );
    expect(
      cache.lastComposedArea,
      lessThanOrEqualTo(4.0 * 32),
      reason: 'the band, not the whole 32×32 view: '
          '${cache.lastComposedArea} canvas px² composited',
    );
  });
}
