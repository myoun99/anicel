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
/// cache (keyed by tile identity) starts from zero. The user's 8K fill
/// showed only the top-left region after a cut round-trip.
///
/// ↩️The painter decoded 32 tiles a paint then, and the rest had to
/// CONVERGE through a completion → notify → repaint chain, which stalled
/// partway; so this waited forty rounds of real time for it. A tile is
/// pictured inside the paint that needs it since 2026-09-17
/// (`BitmapTileImageCache.pictureFor`): the frame that paints the surface
/// pictures every tile of it.
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
        map[coord] = BitmapTile(size: 16, pixels: pixels);
      }
    }
    return BitmapSurface(
      canvasSize: CanvasSize(width: tiles * 16, height: tiles * 16),
      tileSize: 16,
      tiles: map,
    );
  }

  testWidgets('a fully re-materialized surface is pictured whole by the '
      'frame that paints it', (tester) async {
    // 12x12 = 144 tiles: more than four times the 32 a paint used to
    // decode.
    final surface = freshSurface(tiles: 12);

    Widget host(BitmapSurface s) => MaterialApp(
      home: CustomPaint(
        painter: BitmapSurfacePainter(surface: s, lineage: ('l', 'f')),
        child: const SizedBox(width: 200, height: 200),
      ),
    );

    await tester.pumpWidget(host(surface));
    final undecoded = surface.tiles.values
        .where((tile) => BitmapTileImageCache.instance.heldFor(tile) == null)
        .length;
    expect(
      undecoded,
      0,
      reason: 'the frame pictures all 144 tiles (a stall was the 8K '
          'top-left-only bug)',
    );

    // The ROUND-TRIP: a rematerialized surface = all-new tile objects.
    final rematerialized = freshSurface(tiles: 12);
    await tester.pumpWidget(host(rematerialized));
    final undecodedAfter = rematerialized.tiles.values
        .where((tile) => BitmapTileImageCache.instance.heldFor(tile) == null)
        .length;
    expect(
      undecodedAfter,
      0,
      reason: 'and all of them after rematerialization',
    );
  });
}
