import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★ (v) — A STROKE STEP PATCHES THE BUFFER INSTEAD OF REBUILDING IT.
///
/// The buffer exists so the display resamples once; keeping it means an
/// idle frame costs nothing. A stroke is the case that still cost the whole
/// visible rect every step, and this is what took that down to "the dirty
/// rect, plus one opaque copy of what was already right".
///
/// ⛔THE COUNTERS ARE THE CONTRACT, not a debugging aid. An optimisation
/// that never runs looks exactly like one that works, and this session
/// shipped two that did not: a tile grid whose key never matched, and a key
/// that walked every tile and missed anyway. Both were green.
///
/// ★The picture is not allowed to change either — a patch that drifts is
/// worse than no patch — so the parity suites next door still render the
/// same trees and compare pixels.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BitmapSurfacePainter surfaceWith(RgbaColor color, {int at = 0}) {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 8);
    tile = writeRgbaColorToBitmapTile(tile: tile, x: at, y: 0, color: color);
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  testWidgets('the second step patches — only the first pays for everything',
      (tester) async {
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);

    Future<void> pumpWith(BitmapSurfacePainter surface) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 8,
                height: 8,
                child: CanvasLayerStackView(
                  nodes: const [CanvasActiveLayerNode(opacity: 1)],
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  activeSurfacePainter: surface,
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
    }

    final painter = () {
      Future<void> paintOnce() async {
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
        found.paint(Canvas(recorder), const Size(8, 8));
        recorder.endRecording().dispose();
      }

      return paintOnce;
    }();

    // Cold: the buffer has to be composited from nothing, and the decode
    // that lands afterwards makes one more. Both are FULL, and that is the
    // behaviour this feature is not allowed to make worse.
    await pumpWith(surfaceWith(RgbaColor(r: 255, g: 0, b: 0, a: 255)));
    await painter();
    await painter();
    final fullWhileCold = cache.fullCount;
    expect(fullWhileCold, greaterThan(0));
    expect(
      cache.patchedCount,
      0,
      reason: 'nothing to patch against yet — a cold miss must cost exactly '
          'what it always cost',
    );

    // A stroke step: the committed tile is replaced and nothing else moves.
    await pumpWith(
      surfaceWith(RgbaColor(r: 0, g: 0, b: 255, a: 255), at: 1),
    );
    await painter();

    expect(
      cache.patchedCount,
      greaterThan(0),
      reason: 'the live surface moved and nothing else did, so the previous '
          'buffer was right everywhere the stroke did not touch',
    );
  });
}
