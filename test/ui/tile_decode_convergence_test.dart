import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// R27 repro: after a cel round-trip the store REMATERIALIZES the
/// surface — every BitmapTile is a brand-new object, so the tile image
/// cache (keyed by tile identity) starts from zero and the painter's
/// budgeted decode chunks (32/paint) must CONVERGE via the completion →
/// notify → repaint chain. The user's 8K fill showed only the top-left
/// region after a cut round-trip: convergence stalled partway.
void main() {
  BitmapSurface freshSurface({required int tiles}) {
    final map = <TileCoord, BitmapTile>{};
    for (var ty = 0; ty < tiles; ty += 1) {
      for (var tx = 0; tx < tiles; tx += 1) {
        final pixels = Uint8List(16 * 16 * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels[i] = 20;
          pixels[i + 3] = 255;
        }
        final coord = TileCoord(x: tx, y: ty);
        map[coord] = BitmapTile(coord: coord, size: 16, pixels: pixels);
      }
    }
    return BitmapSurface(
      canvasSize: CanvasSize(width: tiles * 16, height: tiles * 16),
      tileSize: 16,
      tiles: map,
    );
  }

  testWidgets('a fully re-materialized surface CONVERGES: every tile '
      'decodes within a bounded number of frames', (tester) async {
    // 12x12 = 144 tiles: needs 5 chunks of 32 — the chain must keep
    // itself alive across at least 5 paint cycles.
    final surface = freshSurface(tiles: 12);

    Widget host(BitmapSurface s) => MaterialApp(
      home: CustomPaint(
        painter: BitmapSurfacePainter(surface: s, staleScope: ('l', 'f')),
        child: const SizedBox(width: 200, height: 200),
      ),
    );

    await tester.pumpWidget(host(surface));
    // Let decode completions land + chain: real async decodes need
    // runAsync-style pumping; pump generously with real waits.
    for (var i = 0; i < 40; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 10),
          ));
      await tester.pump();
    }
    final undecoded = surface.tiles.values
        .where((tile) => BitmapTileImageCache.instance.imageFor(tile) == null)
        .length;
    expect(
      undecoded,
      0,
      reason: 'decode chain must drain all 144 tiles (stall = the 8K '
          'top-left-only bug)',
    );

    // The ROUND-TRIP: a rematerialized surface = all-new tile objects.
    final rematerialized = freshSurface(tiles: 12);
    await tester.pumpWidget(host(rematerialized));
    for (var i = 0; i < 40; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 10),
          ));
      await tester.pump();
    }
    final undecodedAfter = rematerialized.tiles.values
        .where((tile) => BitmapTileImageCache.instance.imageFor(tile) == null)
        .length;
    expect(
      undecodedAfter,
      0,
      reason: 'convergence must also complete after rematerialization',
    );
  });
}
