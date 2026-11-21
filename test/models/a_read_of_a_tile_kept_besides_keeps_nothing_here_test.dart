import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';

/// A read of a tile kept besides keeps nothing here
/// ([BitmapTile.readPixels]) — card
/// `cel-originals-are-held-twice-in-ram-and-on-the-gpu` ②, 저장's draft
/// (2026-11-19): 「CPU 독자 하나만 돌아도 그 타일은 다시 RAM」. Its bytes
/// are the engine's and its cel's kept ones besides
/// ([TilePixelsKeptBesides]): a reader is lent them for its call, and the
/// tile weighs nothing after as before.
///
/// ↩️Every read of a tile the engine made was a copy that stayed: the first
/// CPU reader of a shell's tile brought back the RAM its cel had let go.
void main() {
  const size = defaultCelTileSize;
  final tileBytes = BitmapTile.bytesFor(size);

  late _KeptBesides kept;
  late BitmapTile tile;
  setUp(() {
    kept = _KeptBesides();
    tile = BitmapTile.onEngine(size: size, on: kept);
  });

  /// A tile of bytes of its own that holds what [kept] gives.
  BitmapTile theSameHere() => BitmapTile(
    size: size,
    pixels: Uint8List(tileBytes)..setAll(0, _KeptBesides.bytesOf(size)),
  );

  void expectNothingKept() {
    expect(tile.ownBytes, 0);
    expect(tile.hasItsBytesHere, isFalse);
  }

  test('🚨each reader is lent the bytes and the tile keeps none — read '
      'again by the next', () {
    final came = BitmapTile.timesBytesCameHere;
    final readers = <String, void Function()>{
      'readPixels': () =>
          expect(tile.readPixels((_, view) => view.first), 7),
      'pixels': () => expect(tile.pixels, _KeptBesides.bytesOf(size)),
      'hasInk': () => expect(tile.hasInk, isTrue),
      'inkBounds': () => expect(
        tile.inkBounds,
        (left: 0, top: 0, rightExclusive: size, bottomExclusive: size),
      ),
      'copyPixelsInto': () {
        final into = Uint8List(tileBytes);
        tile.copyPixelsInto(into);
        expect(into, _KeptBesides.bytesOf(size));
      },
      '==': () => expect(tile == theSameHere(), isTrue),
      'hashCode': () => expect(tile.hashCode, theSameHere().hashCode),
      'toJson': () => expect(
        (tile.toJson()['pixels'] as List).first,
        7,
      ),
      'copyWith': () => expect(tile.copyWith() == theSameHere(), isTrue),
    };
    for (final MapEntry(key: name, value: reads) in readers.entries) {
      final before = kept.reads;
      reads();
      expect(kept.reads, greaterThan(before), reason: '$name read it');
      expectNothingKept();
    }
    expect(BitmapTile.timesBytesCameHere, came, reason: 'no weight moved');
  });

  test('what it is known of its ink is asked of no pixel again', () {
    expect(tile.hasInk, isTrue);
    expect(tile.inkBounds, isNotNull);
    final reads = kept.reads;

    expect(tile.hasInk, isTrue);
    expect(tile.inkBounds, isNotNull);

    expect(kept.reads, reads);
  });

  test('the block a read is lent goes back as it returns — and where the '
      'reader throws', () {
    // A side no other tile wears: the blocks held of its size
    // ([TileBlocks.debugHeld]) are this tile's reads' alone.
    const own = 39;
    final ownBytes = BitmapTile.bytesFor(own);
    final lone = BitmapTile.onEngine(size: own, on: kept);
    final laid = TileBlocks.debugLaid(ownBytes);

    final heldWhileRead = lone.readPixels(
      (_, _) => TileBlocks.debugHeld(ownBytes),
    );

    expect(heldWhileRead, 1, reason: '⛔premise: the reader is lent a block');
    expect(TileBlocks.debugHeld(ownBytes), 0);

    expect(
      () => lone.readPixels((_, _) => throw StateError('the reader threw')),
      throwsStateError,
    );
    expect(
      TileBlocks.debugLaid(ownBytes),
      laid + 2,
      reason: '⛔premise: lent a block again',
    );
    expect(TileBlocks.debugHeld(ownBytes), 0);
  });

  test('a read its keeper refuses keeps nothing, and the next reads', () {
    kept.refuses = true;
    expect(() => tile.pixels, throwsStateError);
    expectNothingKept();

    kept.refuses = false;
    expect(tile.pixels, _KeptBesides.bytesOf(size));
  });

  test('said as a string, it reads no pixel', () {
    expect(tile.toString(), contains('$tileBytes'));
    expect(kept.reads, 0);
  });
}

/// A keeper of a tile's bytes besides the engine: a tile of sevens, each
/// read counted.
final class _KeptBesides implements TilePixelsKeptBesides {
  int reads = 0;
  bool refuses = false;

  static Uint8List bytesOf(int size) =>
      Uint8List(BitmapTile.bytesFor(size))
        ..fillRange(0, BitmapTile.bytesFor(size), 7);

  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {
    reads += 1;
    if (refuses) {
      throw StateError('its bytes are kept no more');
    }
    final bytes = BitmapTile.bytesFor(tile.size);
    into.asTypedList(bytes).fillRange(0, bytes, 7);
  }
}
