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
import 'package:anicel/src/ui/canvas/active_layer_flat_projection.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
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
/// ⚠️The second cut had the same disease one level down (2026-09-16).
/// [debugCappedFallbacks] counts a paint that went past the cap BEFORE the
/// flat projection's refusal gate, and nothing here decoded a tile — so the
/// projection refused on cold truth, every measured paint was the direct
/// walk, and the 09-15 numbers are the walk's. "The knee path drew" is
/// [DisplayBufferCache.lastBufferScale], written after that gate; the tiles
/// are decoded for real first (`screen_space_buffer_test`'s way), and the
/// kept buffer is invalidated so the timed paint is the MISS a stroke batch
/// pays rather than the hit the pump's own paint left behind. The flat is
/// also timed alone, and beside it the patch ⏸5b would wire
/// (`ActiveLayerFlatProjection.patchOrNull`), so the probe says which of the
/// two a change actually pays for.
///
/// ⛔Not a pin. Run with `flutter test --run-skipped --tags benchmark <file>`.
/// Knobs: `KNEE_PROBE_SPACING` (512 — one inked tile every N canvas pixels
/// each way), `KNEE_PROBE_ZOOM` (0.09 — the whole width in a 1600 window),
/// `KNEE_PROBE_DECODE` (1 — 0 leaves the tiles cold, which is the walk).
void main() {
  final spacing = int.parse(
    Platform.environment['KNEE_PROBE_SPACING'] ?? '512',
  );
  final zoom = double.parse(Platform.environment['KNEE_PROBE_ZOOM'] ?? '0.09');
  final decode = Platform.environment['KNEE_PROBE_DECODE'] != '0';
  const page = CanvasSize(
    width: CanvasSizeDialog.maxDimension,
    height: CanvasSizeDialog.maxDimension ~/ 2,
  );
  const tileSize = 256;
  const window = Size(1600, 1000);
  final tileImages = BitmapTileImageCache.instance;

  BitmapTile inked(int shade) => writeRgbaColorToBitmapTile(
    tile: BitmapTile.blank(size: tileSize),
    x: 4,
    y: 4,
    color: RgbaColor(r: shade % 256, g: 0, b: 255, a: 255),
  );

  String ms(int micros) => (micros / 1000).toStringAsFixed(2);
  String spread(List<int> micros) {
    final sorted = [...micros]..sort();
    return 'median=${ms(sorted[sorted.length ~/ 2])}ms '
        'p90=${ms(sorted[(sorted.length * 9) ~/ 10])}ms '
        'max=${ms(sorted.last)}ms';
  }

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
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    bool cold() =>
        surface.tiles.values.any((tile) => tileImages.imageFor(tile) == null);

    Future<void> decodeAll() => tester.runAsync(() async {
      for (final entry in surface.tiles.entries) {
        tileImages.ensureDecoded((coord: entry.key, tile: entry.value));
      }
      // Bounded: a decode the engine refuses never lands, and a probe that
      // waits for it forever takes the machine with it.
      for (var i = 0; i < 5000 && cold(); i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    Future<({int fallbacks, bool drew, int micros})> frame() async {
      if (decode) {
        await decodeAll();
      }
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
                debugBufferCache: buffers,
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
      // The pump painted this build already; a stroke batch pays the MISS.
      buffers
        ..invalidate()
        ..lastBufferScale = null;
      final fulls = buffers.fullCount;
      final before = debugCappedFallbacks;
      final watch = Stopwatch()..start();
      final recorder = PictureRecorder();
      painted.first.painter!.paint(Canvas(recorder, Offset.zero & window), window);
      recorder.endRecording().dispose();
      watch.stop();
      return (
        fallbacks: debugCappedFallbacks - before,
        drew: buffers.lastBufferScale != null && buffers.fullCount == fulls + 1,
        micros: watch.elapsedMicroseconds,
      );
    }

    final idle = [for (var i = 0; i < 3; i += 1) await frame()];
    final commits = <({int fallbacks, bool drew, int micros})>[];
    final flatBuilds = <int>[];
    final flatPatches = <int>[];
    ({int width, int height})? flatSize;
    ActiveLayerFlatImage? previousFlat;
    final columns = page.width ~/ tileSize;
    for (var i = 0; i < 30; i += 1) {
      final changed = TileCoord(x: (i * step) % columns, y: 0);
      surface = surface.withRebuiltTiles({changed: inked(i + 7)});
      commits.add(await frame());
      if (!decode) {
        continue;
      }
      // The split: the flat alone, the same call the miss just made — and
      // beside it the patch ⏸5b would wire, from the previous flat with the
      // one coordinate that changed. Neither is drawn, so direct disposes
      // cannot race a recording.
      final watch = Stopwatch()..start();
      final flat = ActiveLayerFlatProjection.buildOrNull(
        surface: surface,
        tileImages: tileImages,
      );
      watch.stop();
      final previous = previousFlat;
      previousFlat = flat;
      if (flat == null) {
        previous?.image.dispose();
        continue;
      }
      flatBuilds.add(watch.elapsedMicroseconds);
      flatSize = (width: flat.image.width, height: flat.image.height);
      if (previous == null) {
        continue;
      }
      final patchWatch = Stopwatch()..start();
      final patched = ActiveLayerFlatProjection.patchOrNull(
        previous: previous,
        changedCoords: {changed},
        surface: surface,
        tileImages: tileImages,
      );
      patchWatch.stop();
      if (patched != null) {
        flatPatches.add(patchWatch.elapsedMicroseconds);
        patched.image.dispose();
      }
      previous.image.dispose();
    }
    previousFlat?.image.dispose();

    final size = flatSize;
    final flatLine = size == null
        ? 'none built'
        : '${size.width}x${size.height} build ${spread(flatBuilds)} | '
              'patch ${flatPatches.isEmpty ? 'none' : spread(flatPatches)}';
    // ignore: avoid_print
    print(
      'knee probe (layer stack): page ${page.width}x${page.height} '
      'tiles ${surface.tiles.length} zoom $zoom decode $decode | idle: '
      'fallbacks=${[for (final f in idle) f.fallbacks]} '
      'drew=${[for (final f in idle) f.drew]} '
      'ms=${[for (final f in idle) ms(f.micros)]} | commit frames: '
      'fallbacks/frame=${{for (final f in commits) f.fallbacks}} '
      'drew/frame=${{for (final f in commits) f.drew}} '
      '${spread([for (final f in commits) f.micros])} | flat alone: $flatLine',
    );
    expect(
      commits.every((f) => f.fallbacks > 0),
      isTrue,
      reason: 'every commit frame went past the cap — a probe that never '
          'falls back measured another route',
    );
    if (decode) {
      expect(
        commits.every((f) => f.drew),
        isTrue,
        reason: 'past the cap is not yet the knee path: a flat that refuses '
            'keeps the walk, and a probe of the walk measured another route',
      );
    }
  });
}
