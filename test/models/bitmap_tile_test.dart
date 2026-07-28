import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('BitmapTile', () {
    test('blank creates transparent pixel buffer', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(tile.pixels, everyElement(0));
    });

    test('blank pixel length is size * size * 4', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 3);
      expect(tile.pixels.length, 3 * 3 * BitmapTile.bytesPerPixel);
    });

    test('constructor accepts valid pixels', () {
      final pixels = Uint8List(16)..[0] = 255;
      final tile = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        pixels: pixels,
      );
      expect(tile.pixels[0], 255);
    });

    test(
      'constructor rejects zero size',
      () => expect(
        () => BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 0,
          pixels: Uint8List(0),
        ),
        throwsArgumentError,
      ),
    );
    test(
      'constructor rejects negative size',
      () => expect(
        () => BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: -1,
          pixels: Uint8List(0),
        ),
        throwsArgumentError,
      ),
    );
    test(
      'constructor rejects wrong pixel length',
      () => expect(
        () => BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
          pixels: Uint8List(15),
        ),
        throwsArgumentError,
      ),
    );

    test('constructor defensively copies input pixels', () {
      final pixels = Uint8List(16)..[0] = 1;
      final tile = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        pixels: pixels,
      );
      pixels[0] = 9;
      expect(tile.pixels[0], 1);
    });

    test('pixels getter returns a defensive copy', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final pixels = tile.pixels..[0] = 9;
      expect(pixels[0], 9);
      expect(tile.pixels[0], 0);
    });

    test('copyWith updates coord', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        tile.copyWith(coord: TileCoord(x: 1, y: 0)).coord,
        TileCoord(x: 1, y: 0),
      );
    });

    test('copyWith updates size and pixels together', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final next = tile.copyWith(size: 3, pixels: Uint8List(36)..[0] = 7);
      expect(next.size, 3);
      expect(next.pixels[0], 7);
    });

    test('equality includes coord, size, and pixel bytes', () {
      final pixels = Uint8List(16)..[0] = 1;
      final tile = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        pixels: pixels,
      );
      expect(
        tile,
        BitmapTile(coord: TileCoord(x: 0, y: 0), size: 2, pixels: pixels),
      );
      expect(tile.copyWith(coord: TileCoord(x: 1, y: 0)), isNot(tile));
      expect(tile.copyWith(size: 1, pixels: Uint8List(4)), isNot(tile));
      expect(tile.copyWith(pixels: Uint8List(16)..[0] = 2), isNot(tile));
    });

    test('toJson/fromJson round-trips', () {
      final tile = BitmapTile(
        coord: TileCoord(x: 1, y: 2),
        size: 2,
        pixels: Uint8List(16)..[3] = 255,
      );
      expectJsonRoundTrip(tile, BitmapTile.fromJson);
    });

    test('byteOffsetForPixel returns expected offset', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 4);
      expect(tile.byteOffsetForPixel(x: 2, y: 1), (1 * 4 + 2) * 4);
    });

    test(
      'byteOffsetForPixel rejects negative x',
      () => expect(
        () => BitmapTile.blank(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
        ).byteOffsetForPixel(x: -1, y: 0),
        throwsArgumentError,
      ),
    );
    test(
      'byteOffsetForPixel rejects negative y',
      () => expect(
        () => BitmapTile.blank(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
        ).byteOffsetForPixel(x: 0, y: -1),
        throwsArgumentError,
      ),
    );
    test(
      'byteOffsetForPixel rejects x >= size',
      () => expect(
        () => BitmapTile.blank(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
        ).byteOffsetForPixel(x: 2, y: 0),
        throwsArgumentError,
      ),
    );
    test(
      'byteOffsetForPixel rejects y >= size',
      () => expect(
        () => BitmapTile.blank(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
        ).byteOffsetForPixel(x: 0, y: 2),
        throwsArgumentError,
      ),
    );

    test('isFullyTransparent is true for blank tile', () {
      expect(
        BitmapTile.blank(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
        ).isFullyTransparent,
        isTrue,
      );
    });

    test('isFullyTransparent is false if any byte is non-zero', () {
      expect(
        BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
          pixels: Uint8List(16)..[0] = 1,
        ).isFullyTransparent,
        isFalse,
      );
    });
  });
}
