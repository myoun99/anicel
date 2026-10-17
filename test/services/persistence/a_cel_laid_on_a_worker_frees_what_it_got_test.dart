@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
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
  // Past the wall (the pasteboard ends at -32), where a file lies.
  final past = TileCoord(x: -6, y: 0);
  final whereTheFileLies = DirtyRegion(
    left: -44,
    top: 0,
    rightExclusive: 4,
    bottomExclusive: 8,
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

  /// Hands that take blocks from `malloc` and count them, giving up on the
  /// [failAt]-th ask.
  ({TileBlockHands hands, List<int> got, List<int> freed}) counted({
    int? failAt,
  }) {
    final got = <int>[];
    final freed = <int>[];
    return (
      hands: (
        allocate: (byteLength) {
          if (got.length == failAt) {
            throw StateError('no block left');
          }
          final block = malloc<Uint8>(byteLength);
          got.add(block.address);
          return block;
        },
        free: (block) {
          freed.add(block.address);
          malloc.free(block);
        },
      ),
      got: got,
      freed: freed,
    );
  }

  test('what it laid is the cel — adopted here, the same tiles, the same '
      'texts and their plates, and the same photos as the copy the main '
      'isolate made', () {
    final entry = entryOf(picture());
    final copied = entry.toSurface();

    final laid = laidCelSurface(
      layCelEntry(entry, tileBlocksHere(BitmapTile.blocks)),
    );

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
    final entry = entryOf(picture());
    final blocks = counted(failAt: 2);

    expect(() => layCelEntry(entry, blocks.hands), throwsStateError);

    expect(blocks.got, hasLength(2), reason: 'premise: two blocks were got');
    expect(blocks.freed, unorderedEquals(blocks.got));
  });

  test('a tile size no tile takes is refused BEFORE the first block — the '
      'main isolate\'s adoption must never be the first to refuse', () {
    final entry = entryOf(picture());
    final blocks = counted();

    expect(
      () => layCelEntry(
        AnicelCelEntry(
          key: entry.key,
          canvasSize: entry.canvasSize,
          tileSize: 0,
          tiles: entry.tiles,
        ),
        blocks.hands,
      ),
      throwsArgumentError,
    );
    expect(blocks.got, isEmpty);
  });

  test('the blocks a worker is told of are this isolate\'s — malloc when it '
      'runs without the engine', () {
    QaNativeEngine.debugForceDartFallback = true;
    addTearDown(() => QaNativeEngine.debugForceDartFallback = false);

    expect(BitmapTile.blocks, (alloc: 0, free: 0));
  });
}
