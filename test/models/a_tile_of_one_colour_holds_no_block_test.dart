import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';

/// A tile every pixel of which is one word holds no block of its own: its
/// pixels are its colour's block, one for every tile of the colour alive
/// (card `a-file-keeps-all-clear-tiles-in-its-cels` — a user's cut kept
/// 27,912 tiles a verb had emptied, each a 64 KB block of one white with no
/// alpha). Whoever reads it reads the bytes it was made of; only its weight
/// differs.
void main() {
  const side = 6;
  final length = BitmapTile.bytesFor(side);

  /// A tile's worth of [rgba], pixel after pixel.
  Uint8List filled(List<int> rgba) {
    final bytes = Uint8List(length);
    for (var at = 0; at < length; at += 1) {
      bytes[at] = rgba[at % 4];
    }
    return bytes;
  }

  /// A white with no alpha — what a destructive verb leaves of a picture's
  /// paper.
  const clearWhite = [255, 255, 255, 0];
  const opaqueRed = [200, 10, 20, 255];

  int addressOf(BitmapTile tile) =>
      tile.readPixels((pointer, _) => pointer.address);

  group('whether pixels are one colour (oneWordOf)', () {
    test('the word of a tile whose pixels are all one, lying anywhere — a '
        'record of a file\'s payload is on no word\'s edge', () {
      final payload = Uint8List(length + 3)..setAll(3, filled(opaqueRed));
      final record = Uint8List.sublistView(payload, 3);

      expect(oneWordOf(record), isNotNull);
      expect(oneWordOf(record), oneWordOf(filled(opaqueRed)));
      expect(
        oneWordOf(filled(clearWhite)),
        isNot(oneWordOf(filled(opaqueRed))),
        reason: 'fixture: two colours are two words',
      );
    });

    test('🚨none where ONE pixel differs, wherever it is — the first, one '
        'in the middle, the last, in any of its four bytes', () {
      for (final pixel in [0, 1, side * side ~/ 2, side * side - 1]) {
        for (var channel = 0; channel < 4; channel += 1) {
          final bytes = filled(clearWhite);
          bytes[pixel * 4 + channel] ^= 1;
          expect(
            oneWordOf(bytes),
            isNull,
            reason: 'pixel $pixel, byte $channel',
          );
        }
      }
    });

    test('🚨an odd number of pixels: they are asked two at a time, and the '
        'last one alone', () {
      Uint8List pixels(int count) {
        final bytes = Uint8List(count * 4);
        for (var at = 0; at < bytes.length; at += 1) {
          bytes[at] = opaqueRed[at % 4];
        }
        return bytes;
      }

      for (final count in [1, 3, 5]) {
        expect(
          oneWordOf(pixels(count)),
          oneWordOf(filled(opaqueRed)),
          reason: '$count pixels of one colour',
        );
        for (var pixel = 1; pixel < count; pixel += 1) {
          for (var channel = 0; channel < 4; channel += 1) {
            final bytes = pixels(count);
            bytes[pixel * 4 + channel] ^= 1;
            expect(
              oneWordOf(bytes),
              isNull,
              reason: '$count pixels, pixel $pixel, byte $channel',
            );
          }
        }
      }
    });

    test('none of no pixel at all', () {
      expect(oneWordOf(Uint8List(0)), isNull);
    });
  });

  group('a tile made of bytes of one colour', () {
    test('🚨reads as the bytes it was made of — by every way a tile is '
        'read', () {
      for (final rgba in [clearWhite, opaqueRed, [0, 0, 0, 0]]) {
        final bytes = filled(rgba);
        final tile = BitmapTile(size: side, pixels: bytes);

        expect(tile.pixels, bytes, reason: '$rgba: pixels');
        expect(
          tile.readPixels((_, view) => Uint8List.fromList(view)),
          bytes,
          reason: '$rgba: the view',
        );
        expect(
          tile.readPixels(
            (pointer, _) => Uint8List.fromList(pointer.asTypedList(length)),
          ),
          bytes,
          reason: '$rgba: the block the engine reads',
        );
        final copy = Uint8List(length);
        tile.copyPixelsInto(copy);
        expect(copy, bytes, reason: '$rgba: copied out');
        expect(tile.holdsBytes(bytes), isTrue, reason: '$rgba: holdsBytes');
      }
    });

    test('🚨holds no block of its own — every tile of the colour reads ONE '
        'block, and weighs nothing', () {
      final one = BitmapTile(size: side, pixels: filled(clearWhite));
      final other = BitmapTile(size: side, pixels: filled(clearWhite));

      expect(addressOf(other), addressOf(one));
      expect(one.ownBytes, 0);
      expect(other.ownBytes, 0);
      expect(ownBytesOf([one, other]), 0);
    });

    test('a tile of another colour, or of another size, reads another '
        'block', () {
      final white = BitmapTile(size: side, pixels: filled(clearWhite));
      final red = BitmapTile(size: side, pixels: filled(opaqueRed));
      final largerWhite = BitmapTile.ofOneColour(
        size: side + 1,
        word: oneWordOf(filled(clearWhite))!,
      );

      expect(addressOf(red), isNot(addressOf(white)));
      expect(addressOf(largerWhite), isNot(addressOf(white)));
      expect(
        largerWhite.pixels,
        hasLength(BitmapTile.bytesFor(side + 1)),
        reason: 'a tile of its own size\'s bytes, not the smaller one\'s',
      );
      expect(largerWhite.pixels.sublist(0, 4), clearWhite);
    });

    test('🚨a tile of two colours holds its own block, and weighs a '
        'tile\'s bytes', () {
      final bytes = filled(clearWhite)..[length - 1] = 9;
      final one = BitmapTile(size: side, pixels: bytes);
      final other = BitmapTile(size: side, pixels: bytes);

      expect(one.pixels, bytes);
      expect(addressOf(other), isNot(addressOf(one)));
      expect(one.ownBytes, length);
      expect(ownBytesOf([one, other]), length * 2);
    });

    test('equals a tile of the same colour, and not one of another', () {
      final white = BitmapTile(size: side, pixels: filled(clearWhite));
      final twoColours = filled(clearWhite)..[0] = 254;

      expect(white, BitmapTile(size: side, pixels: filled(clearWhite)));
      expect(white, isNot(BitmapTile(size: side, pixels: filled(opaqueRed))));
      expect(white, isNot(BitmapTile(size: side, pixels: twoColours)));
      expect(BitmapTile(size: side, pixels: twoColours), isNot(white));
    });
  });

  group('what a tile of one colour knows of its ink', () {
    test('none, and no box, where the colour has no alpha — whatever its '
        'colour bytes', () {
      for (final rgba in [clearWhite, [0, 0, 0, 0]]) {
        final tile = BitmapTile(size: side, pixels: filled(rgba));

        expect(tile.hasInk, isFalse, reason: '$rgba');
        expect(tile.inkBounds, isNull, reason: '$rgba');
        expect(tile.inkBoundsKnown, isTrue, reason: '$rgba');
      }
    });

    test('ink over the whole tile where it has any alpha', () {
      final tile = BitmapTile(size: side, pixels: filled([0, 0, 0, 1]));

      expect(tile.hasInk, isTrue);
      expect(tile.inkBoundsKnown, isTrue);
      expect(tile.inkBounds, (
        left: 0,
        top: 0,
        rightExclusive: side,
        bottomExclusive: side,
      ));
    });
  });

  group('each way a tile is made of bytes asks', () {
    test('a blank tile is the tile of no colour at all', () {
      final blank = BitmapTile.blank(size: side);

      expect(blank.pixels, Uint8List(length));
      expect(blank.ownBytes, 0);
      expect(
        addressOf(blank),
        addressOf(BitmapTile(size: side, pixels: Uint8List(length))),
      );
    });

    test('a tile of a word is the tile of the bytes the word was read '
        'from', () {
      final bytes = filled(const [1, 2, 3, 4]);
      final tile = BitmapTile.ofOneColour(
        size: side,
        word: oneWordOf(bytes)!,
      );

      expect(tile.pixels, bytes);
      expect(addressOf(tile), addressOf(BitmapTile(size: side, pixels: bytes)));
    });

    test('🚨a tile written in place: of one colour it gives its fresh block '
        'back, of two it keeps it', () {
      // A side no other tile wears: the blocks laid and held of its size
      // ([TileBlocks.debugLaid], [TileBlocks.debugHeld]) are this test's
      // alone.
      const ownSide = 26;
      final ownLength = BitmapTile.bytesFor(ownSide);
      final laid = TileBlocks.debugLaid(ownLength);
      final held = TileBlocks.debugHeld(ownLength);

      // The colour's block is the first ask, the written tile's fresh block
      // the second.
      final first = BitmapTile.ofOneColour(size: ownSide, word: 0x01020304);
      final written = BitmapTile.written(
        size: ownSide,
        write: (pixels) => pixels.setAll(0, first.pixels),
      );

      expect(written.pixels, first.pixels);
      expect(written.ownBytes, 0);
      expect(addressOf(written), addressOf(first));
      expect(TileBlocks.debugLaid(ownLength), laid + 2, reason: 'fixture');
      expect(
        TileBlocks.debugHeld(ownLength),
        held + 1,
        reason: 'the block it wrote into went back: the colour\'s alone '
            'is held',
      );

      final twoColours = BitmapTile.written(
        size: ownSide,
        write: (pixels) => pixels
          ..setAll(0, first.pixels)
          ..[0] = 0,
      );
      expect(twoColours.ownBytes, ownLength);
      expect(addressOf(twoColours), isNot(addressOf(first)));
      expect(TileBlocks.debugHeld(ownLength), held + 2);
    });

    test('🚨a write that throws gives its block back — no tile holds it '
        'yet', () {
      // A side of its own, as above.
      const ownSide = 27;
      final ownLength = BitmapTile.bytesFor(ownSide);
      final laid = TileBlocks.debugLaid(ownLength);
      final held = TileBlocks.debugHeld(ownLength);

      expect(
        () => BitmapTile.written(
          size: ownSide,
          write: (_) => throw StateError('the writer failed'),
        ),
        throwsStateError,
      );

      expect(
        TileBlocks.debugLaid(ownLength),
        laid + 1,
        reason: '⛔premise: a block was asked for',
      );
      expect(TileBlocks.debugHeld(ownLength), held);
    });

    test('⚠️a block adopted is adopted unread, whatever its colour — the '
        'worker that laid it was the one to ask', () {
      final block = TileBlocks.alloc(length);
      block.asTypedList(length).setAll(0, filled(clearWhite));

      final adopted = BitmapTile.adoptNative(
        size: side,
        pixels: block,
        hasInk: false,
      );

      expect(addressOf(adopted), block.address);
      expect(adopted.ownBytes, length);
      expect(adopted.pixels, filled(clearWhite));
    });
  });
}
