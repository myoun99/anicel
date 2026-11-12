@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';

/// A cel laid on a worker ([layCelEntry]) and adopted on the main isolate
/// ([laidCelSurface]) — card `cel-thaw-holds-the-ui-thread`: the copies the
/// UI thread used to make, made where they cost the screen nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  // Past the wall (the pasteboard ends at -512), where a file lies.
  final past = TileCoord(x: -6, y: 0);
  final whereTheFileLies = DirtyRegion(
    left: -704,
    top: 0,
    rightExclusive: 64,
    bottomExclusive: 128,
  );

  /// A drawing of two tiles, a file's picture laid past the wall over a
  /// third (F-374-Q8), and a text with a plate — every block a laid cel
  /// holds — and a photo, which holds none.
  BitmapSurface picture() => drawingOf({
    a: tileOf({
      (1, 1): [9, 9, 9, 255],
    }),
    b: tileOf({
      (2, 3): [0, 80, 160, 200],
    }),
  }).copyWith(laidBounds: whereTheFileLies).putTiles([
    (
      coord: past,
      tile: tileOf({
        (5, 1): [7, 7, 7, 255],
      }),
    ),
  ]).withTexts([
    textOf(
      1,
      words: 'laid',
      plate: {
        a: tileOf({
          (4, 4): [200, 0, 0, 128],
        }),
      },
    ),
  ]).withPhotos([photoOf(1)]);

  AnicelCelEntry entryOf(BitmapSurface surface) =>
      AnicelCelEntry.fromSurface(celTextTestKey, surface);

  Map<TileCoord, List<int>> bytesByCoord(Map<TileCoord, BitmapTile> tiles) =>
      {for (final entry in tiles.entries) entry.key: entry.value.pixels};

  // A tile side no other tile in this process wears, so the list of its
  // size ([TileBlocks]) holds what these tests park there and nothing a
  // collected tile's finalizer brings.
  const side = 24;
  final length = BitmapTile.bytesFor(side);

  /// Two blocks of [length] parked on the lists: the addresses the next two
  /// asks of that size are answered with, in that order — the last freed
  /// first.
  List<int> twoParked() {
    final blocks = [TileBlocks.alloc(length), TileBlocks.alloc(length)];
    blocks.forEach(TileBlocks.free);
    return [blocks[1].address, blocks[0].address];
  }

  /// What the next two asks of [length] are answered with, given back when
  /// the test ends.
  List<int> nextTwoAsks() {
    final blocks = [TileBlocks.alloc(length), TileBlocks.alloc(length)];
    addTearDown(() => blocks.forEach(TileBlocks.free));
    return [for (final block in blocks) block.address];
  }

  /// A cel of two whole tiles of [side], then [last].
  AnicelCelEntry twoTilesThen(
    List<AnicelTileRecord> last, {
    int tileSize = side,
  }) => AnicelCelEntry(
    key: celTextTestKey,
    canvasSize: const CanvasSize(width: side * 3, height: side),
    tileSize: tileSize,
    tiles: [
      (x: 0, y: 0, pixels: Uint8List(length)),
      (x: 1, y: 0, pixels: Uint8List(length)),
      ...last,
    ],
  );

  test('what it laid is the cel — adopted here, the same tiles, the same '
      'texts and their plates, and the same photos as the copy the main '
      'isolate made', () {
    final entry = entryOf(picture());
    final copied = entry.toSurface();

    final laid = laidCelSurface(layCelEntry(entry));

    expect(laid.canvasSize, copied.canvasSize);
    expect(laid.tileSize, copied.tileSize);
    expect(bytesByCoord(laid.tiles), bytesByCoord(copied.tiles));
    expect(laid.texts, hasLength(1));
    expect(laid.texts.single.id, copied.texts.single.id);
    expect(laid.texts.single.content, copied.texts.single.content);
    expect(
      bytesByCoord(laid.texts.single.plate),
      bytesByCoord(copied.texts.single.plate),
    );
    expect(laid.photos, copied.photos);
    expect(laid.photos, [photoOf(1)], reason: 'fixture: one came across');
    expect(laid.laidBounds, copied.laidBounds);
    expect(
      laid.tiles.keys,
      contains(past),
      reason: 'fixture: the tile past the wall came across',
    );
  });

  test('🚨a block it could not get frees every block it got — nothing else '
      'knows they exist', () {
    final parked = twoParked();
    // The third tile asks for a block of no bytes, which the lists refuse.
    final entry = twoTilesThen([(x: 2, y: 0, pixels: Uint8List(0))]);

    expect(() => layCelEntry(entry), throwsStateError);

    expect(
      nextTwoAsks(),
      unorderedEquals(parked),
      reason: 'the two it got are parked again: held still, these asks '
          'would be answered with fresh blocks',
    );
  });

  test('a tile size no tile takes is refused BEFORE the first block — the '
      'main isolate\'s adoption must never be the first to refuse', () {
    final parked = twoParked();

    expect(
      () => layCelEntry(twoTilesThen(const [], tileSize: 0)),
      throwsArgumentError,
    );

    expect(
      nextTwoAsks(),
      parked,
      reason: 'the parked blocks lie as they lay: taken and given back, '
          'they would lie the other way round',
    );
  });
}
