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

  // A tile side no other tile in this process wears, so the blocks laid
  // and held of its size ([TileBlocks.debugLaid], [TileBlocks.debugHeld])
  // are what these tests ask for and nothing else.
  const side = 24;
  final length = BitmapTile.bytesFor(side);

  /// The blocks of [length] laid so far, and those held now.
  ({int laid, int held}) blocks() => (
    laid: TileBlocks.debugLaid(length),
    held: TileBlocks.debugHeld(length),
  );

  /// Every cel of [side] a test adopted, held till the file ends: a tile
  /// collected gives its block back when the collector chooses, under a
  /// later test's count.
  final adoptedHere = <BitmapSurface>[];

  /// A tile's worth of two colours — one that takes a block: a tile of one
  /// colour is laid as its word ([LaidPixels]).
  Uint8List twoColours() => Uint8List(length)..[3] = 255;

  /// A cel of two whole tiles of [side], then [last].
  AnicelCelEntry twoTilesThen(
    List<AnicelTileRecord> last, {
    int tileSize = side,
  }) => AnicelCelEntry(
    key: celTextTestKey,
    canvasSize: const CanvasSize(width: side * 3, height: side),
    tileSize: tileSize,
    tiles: [
      (x: 0, y: 0, pixels: twoColours()),
      (x: 1, y: 0, pixels: twoColours()),
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
    final before = blocks();
    // The third tile asks for a block of no bytes, which is refused.
    final entry = twoTilesThen([(x: 2, y: 0, pixels: Uint8List(0))]);

    expect(() => layCelEntry(entry), throwsStateError);

    expect(
      blocks(),
      (laid: before.laid + 2, held: before.held),
      reason: 'the two it got went back',
    );
  });

  test('a tile size no tile takes is refused BEFORE the first block — the '
      'main isolate\'s adoption must never be the first to refuse', () {
    final before = blocks();

    expect(
      () => layCelEntry(twoTilesThen(const [], tileSize: 0)),
      throwsArgumentError,
    );

    expect(
      blocks(),
      before,
      reason: 'no block was asked for: one taken and given back is laid '
          'all the same',
    );
  });

  test('🚨given back unadopted, a text\'s plate goes with the drawing — both '
      'their blocks park again', () {
    final entry = AnicelCelEntry(
      key: celTextTestKey,
      canvasSize: const CanvasSize(width: side, height: side),
      tileSize: side,
      tiles: [(x: 0, y: 0, pixels: twoColours())],
      texts: [
        (
          id: 1,
          content: entryOf(picture()).texts.single.content,
          plate: [(x: 0, y: 0, pixels: twoColours())],
        ),
      ],
    );
    final before = blocks();

    freeLaidCel(layCelEntry(entry));

    expect(blocks(), (laid: before.laid + 2, held: before.held));
  });

  group('a tile of one colour (card '
      '`a-file-keeps-all-clear-tiles-in-its-cels`)', () {
    /// A tile's worth of a white with no alpha — what a destructive verb
    /// leaves of a picture's paper.
    Uint8List clearWhite() {
      final bytes = Uint8List(length)..fillRange(0, length, 255);
      for (var at = 3; at < length; at += 4) {
        bytes[at] = 0;
      }
      return bytes;
    }

    /// A clear white tile, one of two colours, and a clear white one again.
    AnicelCelEntry whiteInkWhite() => AnicelCelEntry(
      key: celTextTestKey,
      canvasSize: const CanvasSize(width: side * 3, height: side),
      tileSize: side,
      tiles: [
        (x: 0, y: 0, pixels: clearWhite()),
        (x: 1, y: 0, pixels: twoColours()),
        (x: 2, y: 0, pixels: clearWhite()),
      ],
    );

    test('🚨takes no block: its word crosses, and one block is asked for '
        'the cel\'s one tile of two colours', () {
      final before = blocks();

      final laid = layCelEntry(whiteInkWhite());
      addTearDown(() => freeLaidCel(laid));

      expect(laid.tiles[0].pixels, isA<LaidWord>());
      expect(laid.tiles[2].pixels, isA<LaidWord>());
      expect(laid.tiles[1].pixels, isA<LaidBlock>());
      expect(
        blocks(),
        (laid: before.laid + 1, held: before.held + 1),
        reason: 'one block asked for, and held: a block taken for a tile '
            'of one colour would be one more laid',
      );
    });

    test('🚨adopted, the cel is the cel the main isolate\'s copy makes — '
        'every tile in its place with its bytes, its colour behind no '
        'alpha too — and weighs its one tile of two colours', () {
      final entry = whiteInkWhite();
      final copied = entry.toSurface();

      final laid = laidCelSurface(layCelEntry(entry));
      adoptedHere.addAll([laid, copied]);

      expect(bytesByCoord(laid.tiles), bytesByCoord(copied.tiles));
      expect(laid.tiles.keys, [
        TileCoord(x: 0, y: 0),
        TileCoord(x: 1, y: 0),
        TileCoord(x: 2, y: 0),
      ]);
      expect(laid.tiles[TileCoord(x: 0, y: 0)]!.pixels, clearWhite());
      expect(laid.keptTileBytes, length);
      expect(copied.keptTileBytes, length);
    });

    test('given back unadopted, the one block it took goes back and '
        'nothing else is freed', () {
      final before = blocks();

      freeLaidCel(layCelEntry(whiteInkWhite()));

      expect(blocks(), (laid: before.laid + 1, held: before.held));
    });
  });
}
