import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨THE DIRTY RECT IS THE DAB, NOT THE STROKE.
///
/// The overlay's tile map ACCUMULATES for the stroke's whole life —
/// nothing leaves it until pen-up — so a dirty pass that unioned "every
/// overlay coordinate" was re-compositing the whole stroke's bounding box
/// on every step: by the third dab of a long line, the patch had quietly
/// grown back into the full-width recomposite the patch exists to avoid.
/// `patchedCount` cannot see this — a bloated patch still counts as one
/// patch — which is why [DisplayBufferCache.lastDirtyRect] exists and why
/// this test asserts on WIDTH, not on whether a patch happened.
///
/// The fix is identity per coordinate, exactly like the committed-tile
/// loop next to it: the overlay replaces a tile's IMAGE only when a dab
/// touched it, so an unchanged image object is "this tile did not move".
void main() {
  // 24×8 at tile size 8: three tile columns, so "the stroke so far" and
  // "the newest dab" live in visibly different rects.
  const canvasSize = CanvasSize(width: 24, height: 8);

  BitmapSurface committedSurface() {
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        for (var x = 0; x < 3; x += 1)
          TileCoord(x: x, y: 0): BitmapTile.blank(
            coord: TileCoord(x: x, y: 0),
            size: 8,
          ),
      },
    );
  }

  BrushDab dabAt(double x, {int sequence = 0}) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  testWidgets('the second dab dirties its own tile, not the whole stroke',
      (tester) async {
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    final surface = committedSurface();
    final painter = BitmapSurfacePainter(
      surface: surface,
      overlayModel: overlay,
      showTransparentBackground: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 24,
              height: 8,
              child: CanvasLayerStackView(
                nodes: const [CanvasActiveLayerNode(opacity: 1)],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: painter,
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
      found.paint(Canvas(recorder), const Size(24, 8));
      recorder.endRecording().dispose();
    }

    // Warm: tokens recorded, buffer kept.
    await paintOnce();
    await paintOnce();

    // Dab 1 lands in tile 0.
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2)], from: 0);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
      );
      await overlay.waitForPendingDecodes();
    });
    await paintOnce();
    final firstDirty = cache.lastDirtyRect;
    expect(firstDirty, isNotNull, reason: 'the dab composed as a patch');

    // Dab 2 lands in tile 2 — the far end of the line. Tile 0's overlay
    // image is untouched by this step.
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2), dabAt(21, sequence: 1)], from: 1);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 19, y: 2, width: 5, height: 5),
      );
      await overlay.waitForPendingDecodes();
    });
    await paintOnce();

    final dirty = cache.lastDirtyRect;
    expect(dirty, isNotNull, reason: 'the dab composed as a patch');
    expect(
      dirty!.left,
      greaterThanOrEqualTo(15),
      reason: 'tile 0 did not move, so the patch must not reach back into '
          'it — under the old union walk this rect spanned the whole '
          'stroke (left 0)',
    );
    expect(
      dirty.width,
      lessThanOrEqualTo(10),
      reason: 'one touched tile plus the hairline inflate',
    );
  });
}
