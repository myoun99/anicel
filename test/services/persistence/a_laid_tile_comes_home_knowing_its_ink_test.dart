import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// A tile a worker lays comes home knowing whether it shows anything: the
/// worker read every byte, and the thread that adopts it reads none to know
/// (card `a-picture-lay-holds-the-raster-thread`, 2026-11-17 — a look
/// letting go of its cels asked it of every tile it shelled, on the UI
/// thread, some 27,000 tiles a sweep of the onion on).
///
/// What the worker said is told apart from what the bytes say by changing
/// the bytes after it laid them: an adoption that read them again would
/// answer the new bytes.
void main() {
  const side = 6;
  final length = BitmapTile.bytesFor(side);

  /// One pixel of red ink at the start, the rest clear: not one colour, so
  /// it lays a block.
  Uint8List inked() => Uint8List(length)
    ..[0] = 200
    ..[3] = 255;

  /// No alpha anywhere, but the colour bytes of the first pixel left
  /// behind — what an eraser leaves: not one colour, and nothing shows.
  Uint8List clearButColoured() => Uint8List(length)..[0] = 200;

  Uint8List bytesOf(LaidPixels laid) =>
      Pointer<Uint8>.fromAddress(
        (laid as LaidBlock).address,
      ).asTypedList(length);

  group('laid as a copy (LaidPixels.copyOf — a cel a worker thaws)', () {
    test('ink comes home known, its bytes unread', () {
      final laid = LaidPixels.copyOf(inked());
      expect(laid, isA<LaidBlock>());
      bytesOf(laid).fillRange(0, length, 0);

      expect(laid.adopted(side).hasInk, isTrue);
    });

    test('nothing shows comes home known too — colour bytes left behind '
        'are no ink', () {
      final laid = LaidPixels.copyOf(clearButColoured());
      expect(laid, isA<LaidBlock>());
      bytesOf(laid)[3] = 255;

      expect(laid.adopted(side).hasInk, isFalse);
    });
  });

  group('laid keeping its block (LaidPixels.keeping — a cut tile)', () {
    Pointer<Uint8> blockOf(Uint8List pixels) {
      final block = TileBlocks.alloc(length);
      block.asTypedList(length).setAll(0, pixels);
      return block;
    }

    test('ink comes home known, its bytes unread', () {
      final block = blockOf(inked());
      final laid = LaidPixels.keeping(block, block.asTypedList(length));
      expect(laid, isA<LaidBlock>());
      bytesOf(laid).fillRange(0, length, 0);

      expect(laid.adopted(side).hasInk, isTrue);
    });

    test('nothing shows comes home known too', () {
      final block = blockOf(clearButColoured());
      final laid = LaidPixels.keeping(block, block.asTypedList(length));
      expect(laid, isA<LaidBlock>());
      bytesOf(laid)[3] = 255;

      expect(laid.adopted(side).hasInk, isFalse);
    });
  });

  test('what a laid tile knows is what a tile of the same bytes answers '
      '(anyInkIn, the one asker)', () {
    for (final pixels in [inked(), clearButColoured()]) {
      expect(
        LaidPixels.copyOf(pixels).adopted(side).hasInk,
        BitmapTile(size: side, pixels: pixels).hasInk,
      );
    }
  });
}
