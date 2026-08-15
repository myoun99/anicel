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
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/static_composite_bake.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// ★S7 — THE BACKDROP RASTER IS A TRADE, AND THE PREDICATE IS ITS PRICE
/// CHECK.
///
/// Before this, `drawRaster` ran unconditionally: a paper-and-one-layer
/// document held a visible-rect image (~9MB at a real view) and paid a
/// re-rasterisation on every key change, to collapse TWO draws into one
/// blit. The predicate is static — replay ops of the node tree, no clock
/// — so it cannot flap within a key, and both mechanisms record the same
/// body, so choosing the picture can never change the pixels.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 8);
  final frameKey = BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: const FrameId('f'),
  );

  LayerFrameImageCache cacheWithDab() {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 5, y: 4),
          color: 0xFF0000FF,
          size: 3,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    return LayerFrameImageCache(frameStore: store);
  }

  Future<
    ({CustomPainter painter, StaticCompositeBake bake})
  > pump(
    WidgetTester tester, {
    required int imageNodesBelow,
    bool disableBake = false,
  }) async {
    // Warmed BEFORE mount so the sync sweep adopts at first build —
    // the bake-extent suite's discipline against the fake-clock race.
    final cache = cacheWithDab();
    await tester.runAsync(
      () => cache.prepare(
        key: frameKey,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 16,
              height: 8,
              child: CanvasLayerStackView(
                nodes: [
                  for (var i = 0; i < imageNodesBelow; i += 1)
                    CanvasLayerImageNode(
                      CanvasLayerImageRequest(frameKey: frameKey, opacity: 1),
                    ),
                  const CanvasActiveLayerNode(opacity: 1),
                ],
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                // A live surface is load-bearing: without it the stack
                // takes the plain walk and the bake never engages.
                activeSurfacePainter: BitmapSurfacePainter(
                  surface: BitmapSurface(
                    canvasSize: canvasSize,
                    tileSize: 8,
                    tiles: {
                      for (var x = 0; x < 2; x += 1)
                        TileCoord(x: x, y: 0): BitmapTile.blank(
                          coord: TileCoord(x: x, y: 0),
                          size: 8,
                        ),
                    },
                  ),
                  showTransparentBackground: false,
                ),
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFF00FF00),
                debugDisableBake: disableBake,
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
    return (painter: painter, bake: bake);
  }

  Future<Uint8List> paintBytes(
    WidgetTester tester,
    CustomPainter painter,
  ) async {
    return tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(16, 8));
      final picture = recorder.endRecording();
      final image = picture.toImageSync(16, 8);
      picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }).then((bytes) => bytes!);
  }

  testWidgets('a light stack keeps the picture — no visible-rect image, '
      'same pixels as the raw walk', (tester) async {
    // Paper + one layer: two replay ops. The blit would save one.
    final mounted = await pump(tester, imageNodesBelow: 1);
    final withBake = await paintBytes(tester, mounted.painter);

    expect(
      mounted.bake.rasterCount,
      0,
      reason: 'holding megabytes to collapse two draws into one is the '
          'trade the predicate exists to refuse',
    );
    expect(
      mounted.bake.slotCount,
      greaterThan(0),
      reason: 'refusing the raster must not refuse the bake — the backdrop '
          'still records once as a picture',
    );

    // Pixel anchor: the picture fallback draws the raw walk's picture.
    final raw = await pump(tester, imageNodesBelow: 1, disableBake: true);
    expect(await paintBytes(tester, raw.painter), withBake);
  });

  testWidgets('a heavy stack collapses into the blit', (tester) async {
    // Paper + seven draws: the threshold. This is the document class the
    // raster exists for, shrunk to fixture size.
    final mounted = await pump(tester, imageNodesBelow: 7);
    await paintBytes(tester, mounted.painter);

    expect(
      mounted.bake.rasterCount,
      1,
      reason: 'past the threshold the bottom of the stack is one blit',
    );
  });
}
