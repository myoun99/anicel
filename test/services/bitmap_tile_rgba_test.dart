import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';

void main() {
  group('readRgbaColorFromBitmapTile', () {
    test('reads transparent pixel from blank tile', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);

      expect(
        readRgbaColorFromBitmapTile(tile: tile, x: 0, y: 0),
        RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
    });

    test('reads RGBA bytes in R,G,B,A order', () {
      final tile = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        pixels: Uint8List.fromList([
          0,
          0,
          0,
          0,
          1,
          2,
          3,
          4,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      );

      expect(
        readRgbaColorFromBitmapTile(tile: tile, x: 1, y: 0),
        RgbaColor(r: 1, g: 2, b: 3, a: 4),
      );
    });

    test('rejects negative x', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => readRgbaColorFromBitmapTile(tile: tile, x: -1, y: 0),
        throwsArgumentError,
      );
    });

    test('rejects negative y', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => readRgbaColorFromBitmapTile(tile: tile, x: 0, y: -1),
        throwsArgumentError,
      );
    });

    test('rejects x >= tile.size', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => readRgbaColorFromBitmapTile(tile: tile, x: 2, y: 0),
        throwsArgumentError,
      );
    });

    test('rejects y >= tile.size', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => readRgbaColorFromBitmapTile(tile: tile, x: 0, y: 2),
        throwsArgumentError,
      );
    });
  });

  group('writeRgbaColorToBitmapTile', () {
    test('writes RGBA bytes in R,G,B,A order', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final updated = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 1,
        y: 0,
        color: RgbaColor(r: 1, g: 2, b: 3, a: 4),
      );

      expect(updated.pixels.sublist(4, 8), [1, 2, 3, 4]);
    });

    test('returns a new BitmapTile', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final updated = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 0,
        y: 0,
        color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );

      expect(identical(updated, tile), isFalse);
    });

    test('does not mutate original tile', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final updated = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 1,
        y: 0,
        color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );

      expect(
        readRgbaColorFromBitmapTile(tile: tile, x: 1, y: 0),
        RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
      expect(
        readRgbaColorFromBitmapTile(tile: updated, x: 1, y: 0),
        RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );
    });

    test('preserves tile coord', () {
      final coord = TileCoord(x: 3, y: 4);
      final tile = BitmapTile.blank(coord: coord, size: 2);
      final updated = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 0,
        y: 0,
        color: RgbaColor(r: 0, g: 255, b: 0, a: 128),
      );

      expect(updated.coord, coord);
    });

    test('preserves tile size', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final updated = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 0,
        y: 0,
        color: RgbaColor(r: 0, g: 255, b: 0, a: 128),
      );

      expect(updated.size, 2);
    });

    test('only changes the target pixel', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final updated = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 1,
        y: 0,
        color: RgbaColor(r: 1, g: 2, b: 3, a: 4),
      );

      expect(
        readRgbaColorFromBitmapTile(tile: updated, x: 0, y: 0),
        RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
      expect(
        readRgbaColorFromBitmapTile(tile: updated, x: 1, y: 0),
        RgbaColor(r: 1, g: 2, b: 3, a: 4),
      );
      expect(
        readRgbaColorFromBitmapTile(tile: updated, x: 0, y: 1),
        RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
      expect(
        readRgbaColorFromBitmapTile(tile: updated, x: 1, y: 1),
        RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
    });

    test('rejects negative x', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => writeRgbaColorToBitmapTile(
          tile: tile,
          x: -1,
          y: 0,
          color: RgbaColor(r: 0, g: 255, b: 0, a: 128),
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative y', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => writeRgbaColorToBitmapTile(
          tile: tile,
          x: 0,
          y: -1,
          color: RgbaColor(r: 0, g: 255, b: 0, a: 128),
        ),
        throwsArgumentError,
      );
    });

    test('rejects x >= tile.size', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => writeRgbaColorToBitmapTile(
          tile: tile,
          x: 2,
          y: 0,
          color: RgbaColor(r: 0, g: 255, b: 0, a: 128),
        ),
        throwsArgumentError,
      );
    });

    test('rejects y >= tile.size', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        () => writeRgbaColorToBitmapTile(
          tile: tile,
          x: 0,
          y: 2,
          color: RgbaColor(r: 0, g: 255, b: 0, a: 128),
        ),
        throwsArgumentError,
      );
    });
  });
}
