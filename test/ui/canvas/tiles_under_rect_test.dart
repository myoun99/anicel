import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/tiles_under_rect.dart';

/// A canvas-space Rect reaches every tile its floor/ceil hull touches — a
/// fractional edge still covers the tile it pokes into. The mutation that
/// floored the right edge survived every painter pin (their views end on
/// whole pixels); this reads the hull directly.
void main() {
  BitmapSurface surfaceWith(List<int> xs) => BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 4),
    tileSize: 4,
    tiles: {
      for (final x in xs)
        TileCoord(x: x, y: 0): BitmapTile.blank(
          size: 4,
        ),
    },
  );

  List<int> xsUnder(BitmapSurface surface, Rect rect) => [
    for (final covered in tilesUnderRect(surface, rect)) covered.coord.x,
  ];

  test('a fractional right edge reaches the tile it pokes into', () {
    final surface = surfaceWith([0, 1, 2, 3]);
    expect(xsUnder(surface, const Rect.fromLTRB(0.5, 0, 8.5, 1)), [0, 1, 2]);
    expect(xsUnder(surface, const Rect.fromLTRB(4, 0, 8, 1)), [1]);
  });

  test('a fractional left edge reaches the tile it pokes into, negative '
      'included', () {
    final surface = surfaceWith([-1, 0]);
    expect(xsUnder(surface, const Rect.fromLTRB(-0.5, 0, 0.5, 1)), [-1, 0]);
    expect(xsUnder(surface, const Rect.fromLTRB(3.5, 0, 4, 1)), [0]);
  });

  test('an empty rect covers nothing', () {
    final surface = surfaceWith([0]);
    expect(xsUnder(surface, const Rect.fromLTRB(2, 0, 2, 1)), isEmpty);
    expect(xsUnder(surface, const Rect.fromLTRB(3, 1, 2, 0)), isEmpty);
  });

  test('a missing tile is skipped', () {
    final surface = surfaceWith([2]);
    expect(xsUnder(surface, const Rect.fromLTRB(0, 0, 16, 4)), [2]);
  });
}
