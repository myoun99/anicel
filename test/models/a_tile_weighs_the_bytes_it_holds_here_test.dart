import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';

/// A tile weighs the bytes it holds HERE ([BitmapTile.ownBytes]) — card
/// `cel-originals-are-held-twice-in-ram-and-on-the-gpu` ②, 저장's draft
/// (2026-11-19): 「「여기 든 바이트」로 센다」. One the engine made weighs
/// nothing while its pixels lie on the engine alone, and a tile's bytes
/// once they are read here or its copy is handed it: the one weight that
/// moves, and each time it does is counted
/// ([BitmapTile.timesBytesCameHere]) for whoever keeps a sum of weights
/// (`HotCelWeights`).
///
/// ↩️It weighed a tile's bytes wherever they lay: a shell's tile, which
/// holds none here, stood as RAM in what the looks hold beside their store
/// and in the census.
void main() {
  const size = defaultCelTileSize;
  final tileBytes = BitmapTile.bytesFor(size);

  BitmapTile madeOnEngine({bool refused = false}) =>
      BitmapTile.onEngine(size: size, on: _Engine(refused: refused));

  test('🚨a tile the engine made weighs nothing till its bytes are read '
      'here, and a tile\'s bytes from then on', () {
    final tile = madeOnEngine();

    expect(tile.ownBytes, 0);
    expect(tile.mayWeighMore, isTrue);
    final came = BitmapTile.timesBytesCameHere;

    tile.readPixels((_, _) {});

    expect(tile.ownBytes, tileBytes);
    expect(tile.mayWeighMore, isFalse);
    expect(BitmapTile.timesBytesCameHere, came + 1);

    tile.readPixels((_, _) {});

    expect(
      BitmapTile.timesBytesCameHere,
      came + 1,
      reason: 'read where they lie now: nothing came',
    );
  });

  test('handed its copy, it weighs a tile\'s bytes, and they are said to '
      'have come', () {
    final tile = madeOnEngine();
    final came = BitmapTile.timesBytesCameHere;

    tile.keepBytesHere(Uint8List(tileBytes)..[3] = 255);

    expect(tile.ownBytes, tileBytes);
    expect(tile.mayWeighMore, isFalse);
    expect(BitmapTile.timesBytesCameHere, came + 1);
  });

  test('a read the engine refuses leaves it weighing nothing, and nothing '
      'said to have come', () {
    final tile = madeOnEngine(refused: true);
    final came = BitmapTile.timesBytesCameHere;

    expect(() => tile.readPixels((_, _) {}), throwsStateError);

    expect(tile.ownBytes, 0);
    expect(tile.mayWeighMore, isTrue);
    expect(BitmapTile.timesBytesCameHere, came);
  });

  test('a tile made here weighs what it did as it was made, and never '
      'more', () {
    final ofItsOwn = BitmapTile(
      size: size,
      pixels: Uint8List(tileBytes)..[3] = 255,
    );
    final ofAColour = BitmapTile.blank(size: size);

    expect(ofItsOwn.ownBytes, tileBytes);
    expect(ofItsOwn.mayWeighMore, isFalse);
    expect(ofAColour.ownBytes, 0);
    expect(ofAColour.mayWeighMore, isFalse);
  });
}

/// The engine as a tile reads it: a tile of sevens, or a refusal.
final class _Engine implements TilePixelsOnEngine {
  _Engine({required this.refused});

  final bool refused;

  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {
    if (refused) {
      throw StateError('the device is gone');
    }
    final bytes = BitmapTile.bytesFor(tile.size);
    into.asTypedList(bytes).fillRange(0, bytes, 7);
  }
}
