@Tags(['benchmark'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// CANVAS lightening probe — the COLLECT pass's cost ceiling.
///
/// The painter now DRAWS only the tile coordinates the view covers
/// (O(visible), pinned by the "off-screen committed tile is not drawn"
/// test in bitmap_surface_painter_test.dart). What still walks the whole
/// cel is the DECODE-START collect pass: an Expando lookup per committed
/// tile, kept whole so off-screen tiles pre-warm in the background and
/// scroll in already decoded.
///
/// This times that collect walk at its WORST — no cache images, so every
/// tile answers needsDecodeStart and gets appended. It is the ceiling: in
/// production most committed tiles are already decoded, so the lookup
/// returns false and nothing is appended. Before the draw path was made
/// visible-only this walk ALSO issued a drawImage per tile and cost
/// ~2.2ms at 1024 tiles; the collect-only walk is ~0.1ms there. The
/// number to watch is that the collect walk stays cheap — if it ever
/// creeps back toward milliseconds, the pre-warm is too eager.
///
/// Prints; ratios within a run only.
void main() {
  BitmapSurface filledSurface(int tileCount) {
    const tileSize = 256;
    final canvas = CanvasSize(width: tileSize * tileCount, height: tileSize);
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 3; i < pixels.length; i += 4) {
        pixels[i] = 255;
      }
      final tile = BitmapTile(
        coord: TileCoord(x: x, y: 0),
        size: tileSize,
        pixels: pixels,
      );
      tiles[tile.coord] = tile;
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  double paintMicros(BitmapSurface surface) {
    // The view is panned FAR off every tile (they all sit on row y=0),
    // so nothing is visible: the pixel fallback never fires and what is
    // left is the pure per-tile walk — the map iteration + Expando
    // lookups that happen whether or not a tile is on screen.
    final viewport = CanvasViewport(zoom: 4.0, panY: -100000);
    final cache = BitmapTileImageCache();
    const rounds = 200;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final watch = Stopwatch()..start();
    for (var round = 0; round < rounds; round += 1) {
      BitmapSurfacePainter(
        surface: surface,
        viewport: viewport,
        showTransparentBackground: false,
        tileImageCache: cache,
      ).paint(canvas, const Size(256, 256));
    }
    watch.stop();
    recorder.endRecording().dispose();
    return watch.elapsedMicroseconds / rounds;
  }

  test('surface paint cost vs off-screen committed tile count', () {
    // ignore: avoid_print
    print('--- surface painter tile-walk (ratios, not absolutes)');
    paintMicros(filledSurface(8)); // warmup, discarded

    double? base;
    for (final count in const [16, 64, 256, 1024]) {
      final us = paintMicros(filledSurface(count));
      base ??= us;
      // ignore: avoid_print
      print(
        '$count tiles (1 on-screen): '
        '${us.toStringAsFixed(1)}us/paint '
        '(${(us / base).toStringAsFixed(2)}x of 16-tile)',
      );
      expect(us, greaterThan(0));
    }
  });
}
