import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';

/// R26 #13 follow-up: the tight ink bounding box — the whole-picture
/// transform box frames exactly the picture.
void main() {
  const tileSize = 4;

  BitmapTile tileWithInk(
    TileCoord coord,
    List<({int x, int y})> inkedPixels, {
    int alpha = 255,
  }) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (final pixel in inkedPixels) {
      final base = (pixel.y * tileSize + pixel.x) * 4;
      pixels[base] = 255;
      pixels[base + 3] = alpha;
    }
    return BitmapTile(coord: coord, size: tileSize, pixels: pixels);
  }

  test('spans ink across tiles, in canvas coordinates', () {
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 12, height: 12),
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): tileWithInk(TileCoord(x: 0, y: 0), [
          (x: 2, y: 1),
        ]),
        TileCoord(x: 2, y: 1): tileWithInk(TileCoord(x: 2, y: 1), [
          (x: 3, y: 2),
        ]),
      },
    );

    expect(
      bitmapSurfaceContentBounds(surface),
      (left: 2, top: 1, rightExclusive: 12, bottomExclusive: 7),
    );
  });

  test('alpha-zero pixels are NOT ink (colored-but-transparent bytes '
      'never widen the box); a blank surface answers null', () {
    final ghostInk = BitmapSurface(
      canvasSize: const CanvasSize(width: 8, height: 8),
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): tileWithInk(TileCoord(x: 0, y: 0), [
          (x: 0, y: 0),
        ], alpha: 0),
        TileCoord(x: 1, y: 1): tileWithInk(TileCoord(x: 1, y: 1), [
          (x: 1, y: 1),
        ]),
      },
    );
    expect(
      bitmapSurfaceContentBounds(ghostInk),
      (left: 5, top: 5, rightExclusive: 6, bottomExclusive: 6),
    );

    expect(
      bitmapSurfaceContentBounds(
        BitmapSurface(
          canvasSize: const CanvasSize(width: 8, height: 8),
          tileSize: tileSize,
        ),
      ),
      isNull,
    );
  });
}
