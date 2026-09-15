@Tags(['benchmark'])
library;

import 'dart:io' show Platform;
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/dialogs/canvas_size_dialog.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🔬tile-commit-path-audit, the last item (2026-09-15): what a frame costs
/// on the knee path — the screen-scale buffer the layer stack composes PAST
/// THE BUFFER CAP, where `ActiveLayerFlatProjection.buildOrNull` walks the
/// whole cel and rasters it flat — when the cel changes every frame.
///
/// ⚠️The first cut pumped `BrushCanvasPanel` alone and read ZERO capped
/// fallbacks on every frame: the panel's ink view paints the cel itself, and
/// the knee lives in the LAYER STACK's paint pass — it measured a route that
/// never reaches the knee. This drives `CanvasLayerStackView` the way
/// `one_resolution_at_every_zoom_test` does (the counter moves only inside
/// an explicit paint), and fails instead of reporting when a measured frame
/// did not fall back.
///
/// ⛔Not a pin. Run with `flutter test --run-skipped --tags benchmark <file>`.
/// Knobs: `KNEE_PROBE_SPACING` (512 — one inked tile every N canvas pixels
/// each way), `KNEE_PROBE_ZOOM` (0.09 — the whole width in a 1600 window).
void main() {
  final spacing = int.parse(
    Platform.environment['KNEE_PROBE_SPACING'] ?? '512',
  );
  final zoom = double.parse(Platform.environment['KNEE_PROBE_ZOOM'] ?? '0.09');
  const page = CanvasSize(
    width: CanvasSizeDialog.maxDimension,
    height: CanvasSizeDialog.maxDimension ~/ 2,
  );
  const tileSize = 256;
  const window = Size(1600, 1000);

  BitmapTile inked(int shade) => writeRgbaColorToBitmapTile(
    tile: BitmapTile.blank(size: tileSize),
    x: 4,
    y: 4,
    color: RgbaColor(r: shade % 256, g: 0, b: 255, a: 255),
  );

  testWidgets('a cel that changes every frame, on the largest page, zoomed '
      'out past the buffer cap', (tester) async {
    await tester.binding.setSurfaceSize(window);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final step = (spacing ~/ tileSize).clamp(1, page.width ~/ tileSize);
    var surface = BitmapSurface(
      canvasSize: page,
      tileSize: tileSize,
      tiles: {
        for (var y = 0; y * tileSize < page.height; y += step)
          for (var x = 0; x * tileSize < page.width; x += step)
            TileCoord(x: x, y: y): inked(x + y),
      },
    );
    final imageCache = LayerFrameImageCache(frameStore: BrushFrameStore());

    Future<({int fallbacks, int micros})> frame() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: window.width,
              height: window.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasActiveLayerRow(opacity: 1),
                  ),
                ],
                imageCache: imageCache,
                canvasSize: page,
                viewport: CanvasViewport(zoom: zoom),
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
      );
      final painted = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(CanvasLayerStackView),
              matching: find.byType(CustomPaint),
            ),
          )
          .where((paint) => paint.painter != null)
          .toList();
      expect(painted, isNotEmpty, reason: 'the stack mounted a painter');
      final before = debugCappedFallbacks;
      final watch = Stopwatch()..start();
      final recorder = PictureRecorder();
      painted.first.painter!.paint(Canvas(recorder, Offset.zero & window), window);
      recorder.endRecording().dispose();
      watch.stop();
      return (
        fallbacks: debugCappedFallbacks - before,
        micros: watch.elapsedMicroseconds,
      );
    }

    final idle = [for (var i = 0; i < 3; i += 1) await frame()];
    final commits = <({int fallbacks, int micros})>[];
    final columns = page.width ~/ tileSize;
    for (var i = 0; i < 30; i += 1) {
      surface = surface.withRebuiltTiles({
        TileCoord(x: (i * step) % columns, y: 0): inked(i + 7),
      });
      commits.add(await frame());
    }

    final micros = [for (final f in commits) f.micros]..sort();
    String ms(int value) => (value / 1000).toStringAsFixed(2);
    // ignore: avoid_print
    print(
      'knee probe (layer stack): page ${page.width}x${page.height} '
      'tiles ${surface.tiles.length} zoom $zoom | idle: '
      'fallbacks=${[for (final f in idle) f.fallbacks]} '
      'ms=${[for (final f in idle) ms(f.micros)]} | commit frames: '
      'fallbacks/frame=${{for (final f in commits) f.fallbacks}} '
      'median=${ms(micros[micros.length ~/ 2])}ms '
      'p90=${ms(micros[(micros.length * 9) ~/ 10])}ms '
      'max=${ms(micros.last)}ms',
    );
    expect(
      commits.every((f) => f.fallbacks > 0),
      isTrue,
      reason: 'every commit frame is on the knee path — a probe that never '
          'falls back measured another route',
    );
  });
}
