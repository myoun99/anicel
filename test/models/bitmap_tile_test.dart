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

    test('rebasedTo updates coord', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      expect(
        tile.rebasedTo(TileCoord(x: 1, y: 0)).coord,
        TileCoord(x: 1, y: 0),
      );
    });

    /// 🚨★★★**A WHOLE-TILE SHIFT COPIED EVERY PIXEL TO CHANGE TWO
    /// INTEGERS.** An anchored canvas resize whose offset is a multiple
    /// of the tile size moves nothing WITHIN a tile — it renames it. It
    /// went through `copyWith`, which allocates a fresh native buffer and
    /// memcpys the whole tile into it, over every cel of the cut.
    ///
    /// ⛔A copy and a share answer every BEHAVIOURAL question the same
    /// way, which is why this asks about the bytes themselves.
    test('🚨a rebase SHARES the pixel buffer — it does not copy it', () {
      final tile = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        pixels: Uint8List(16)..[0] = 5,
      );
      final moved = tile.rebasedTo(TileCoord(x: 1, y: 0));

      expect(moved.coord, TileCoord(x: 1, y: 0));
      expect(
        tile.readPixels((pointer, _) => pointer.address),
        moved.readPixels((pointer, _) => pointer.address),
        reason: 'the same native block, not a duplicate of it',
      );
      expect(moved.pixels[0], 5);
    });

    test('a rebase to the SAME coord is the same object', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 3, y: 4), size: 2);
      expect(identical(tile.rebasedTo(TileCoord(x: 3, y: 4)), tile), isTrue);
    });

    /// The chain stays FLAT: a rebase of a rebase points at the original,
    /// not at the tile it came from. Nested owners would keep every
    /// intermediate alive for the life of the last one.
    test('a rebase of a rebase still shares the ORIGINAL block', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final once = tile.rebasedTo(TileCoord(x: 1, y: 0));
      final twice = once.rebasedTo(TileCoord(x: 2, y: 0));
      expect(
        tile.readPixels((pointer, _) => pointer.address),
        twice.readPixels((pointer, _) => pointer.address),
      );
    });

    /// The scans come along too: they are decided by the pixels, and
    /// these are the very same pixels.
    test('a rebase inherits the ink answers instead of rescanning', () {
      final inked = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        pixels: Uint8List(16)..[3] = 255,
      );
      expect(inked.inkBounds, isNotNull);
      expect(inked.inkBoundsKnown, isTrue);

      final moved = inked.rebasedTo(TileCoord(x: 1, y: 0));
      expect(moved.inkBoundsKnown, isTrue);
      expect(moved.inkBounds, inked.inkBounds);
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
      expect(tile.rebasedTo(TileCoord(x: 1, y: 0)), isNot(tile));
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

    test('a blank tile has no ink', () {
      expect(
        BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2).hasInk,
        isFalse,
      );
    });

    test('one opaque pixel is ink', () {
      expect(
        BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
          pixels: Uint8List(16)..[3] = 1,
        ).hasInk,
        isTrue,
      );
    });

    /// 🚨THE CASE THE DELETED TWIN ANSWERED DIFFERENTLY. `isFullyTransparent`
    /// read every byte, so a tile carrying colour behind zero alpha was
    /// "not blank" to it and "no ink" to this — two answers to one
    /// question, live in the same codebase (deleted 2026-09-08). This one
    /// is the answer that matches what the screen does: source-over draws
    /// nothing at alpha 0 whatever the colour bytes say.
    test('colour behind zero alpha is NOT ink', () {
      expect(
        BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 2,
          pixels: Uint8List(16)..[0] = 255,
        ).hasInk,
        isFalse,
      );
    });
  });
}
