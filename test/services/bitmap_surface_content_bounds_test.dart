import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';

/// R26 #13 follow-up: the tight ink bounding box — the whole-picture
/// transform box frames exactly the picture.
void main() {
  const tileSize = defaultCelTileSize;

  PlacedTile tileWithInk(
    TileCoord coord,
    List<({int x, int y})> inkedPixels, {
    int alpha = 255,
  }) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (final pixel in inkedPixels) {
      final base = (pixel.y * tileSize + pixel.x) * 4;
      pixels[base] = 255;
      pixels[base + 3] = alpha;
    }
    return (coord: coord, tile: BitmapTile(size: tileSize, pixels: pixels));
  }

  test('spans ink across tiles, in canvas coordinates', () {
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 3 * tileSize, height: 3 * tileSize),
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): tileWithInk(TileCoord(x: 0, y: 0), [
          (x: 2, y: 1),
        ]).tile,
        TileCoord(x: 2, y: 1): tileWithInk(TileCoord(x: 2, y: 1), [
          (x: 3, y: 2),
        ]).tile,
      },
    );

    expect(bitmapSurfaceContentBounds(surface), (
      left: 2,
      top: 1,
      rightExclusive: 2 * tileSize + 4,
      bottomExclusive: tileSize + 3,
    ));
  });

  test('🚨the box reaches the FARTHEST ink in a tile, not the first — a '
      'run inside one tile has a left and a right', () {
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 3 * tileSize, height: 3 * tileSize),
      tileSize: tileSize,
      tiles: {
        // One tile, ink from (1,0) to (3,2): the box has to be three
        // wide and three tall. Every earlier fixture inked a SINGLE
        // pixel per tile, so left == right and top == bottom, and a
        // fold that kept the near edge for both read as correct.
        TileCoord(x: 1, y: 1): tileWithInk(TileCoord(x: 1, y: 1), [
          (x: 1, y: 0),
          (x: 3, y: 2),
        ]).tile,
      },
    );

    expect(bitmapSurfaceContentBounds(surface), (
      left: tileSize + 1,
      top: tileSize,
      rightExclusive: tileSize + 4,
      bottomExclusive: tileSize + 3,
    ));
  });

  test('alpha-zero pixels are NOT ink (colored-but-transparent bytes '
      'never widen the box); a blank surface answers null', () {
    final ghostInk = BitmapSurface(
      canvasSize: const CanvasSize(width: 2 * tileSize, height: 2 * tileSize),
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): tileWithInk(TileCoord(x: 0, y: 0), [
          (x: 0, y: 0),
        ], alpha: 0).tile,
        TileCoord(x: 1, y: 1): tileWithInk(TileCoord(x: 1, y: 1), [
          (x: 1, y: 1),
        ]).tile,
      },
    );
    expect(bitmapSurfaceContentBounds(ghostInk), (
      left: tileSize + 1,
      top: tileSize + 1,
      rightExclusive: tileSize + 2,
      bottomExclusive: tileSize + 2,
    ));

    expect(
      bitmapSurfaceContentBounds(
        BitmapSurface(
          canvasSize: const CanvasSize(
            width: 2 * tileSize,
            height: 2 * tileSize,
          ),
          tileSize: tileSize,
        ),
      ),
      isNull,
    );
  });

  /// 🚨★★★**THE COMMIT'S HALF OF THE ANSWER.** Callers memoize the box on
  /// the SURFACE instance — and a commit makes a new instance, so before
  /// this the whole cel was rescanned, per commit, while the user drew.
  /// The pixels had not moved: every tile a commit does not touch is the
  /// SAME OBJECT in the new surface, and a tile is immutable.
  ///
  /// ⛔The behavioural answer cannot see this — a rescan and a memo agree
  /// on every box. What can see it is whether the tile still OWES one.
  group('🚨the ink box is memoized per tile, so a commit rescans only what '
      'it touched', () {
    test('a scan leaves every inked tile knowing its own box', () {
      final untouched = tileWithInk(TileCoord(x: 0, y: 0), [(x: 2, y: 1)]);
      expect(
        untouched.tile.inkBoundsKnown,
        isFalse,
        reason: 'a fresh tile has scanned nothing yet',
      );

      bitmapSurfaceContentBounds(
        BitmapSurface(
          canvasSize: const CanvasSize(
            width: 3 * tileSize,
            height: 3 * tileSize,
          ),
          tileSize: tileSize,
          tiles: {untouched.coord: untouched.tile},
        ),
      );

      expect(untouched.tile.inkBoundsKnown, isTrue);
      expect(untouched.tile.inkBounds, (
        left: 2,
        top: 1,
        rightExclusive: 3,
        bottomExclusive: 2,
      ));
    });

    test('the tiles a commit carried over owe nothing on the next scan', () {
      final untouched = tileWithInk(TileCoord(x: 0, y: 0), [(x: 2, y: 1)]);
      final before = BitmapSurface(
        canvasSize: const CanvasSize(width: 3 * tileSize, height: 3 * tileSize),
        tileSize: tileSize,
        tiles: {untouched.coord: untouched.tile},
      );
      bitmapSurfaceContentBounds(before);

      // What a commit does: one tile replaced, every other tile carried
      // over by reference.
      final committed = tileWithInk(TileCoord(x: 2, y: 1), [(x: 3, y: 2)]);
      final after = before.putTiles([committed]);
      expect(
        identical(after.tileAt(untouched.coord), untouched.tile),
        isTrue,
      );
      expect(
        committed.tile.inkBoundsKnown,
        isFalse,
        reason: 'the tile the stroke made is the one that still owes a scan',
      );

      expect(bitmapSurfaceContentBounds(after), (
        left: 2,
        top: 1,
        rightExclusive: 2 * tileSize + 4,
        bottomExclusive: tileSize + 3,
      ));
      // And the carried-over tile answered from its memo throughout.
      expect(untouched.tile.inkBoundsKnown, isTrue);
      expect(committed.tile.inkBoundsKnown, isTrue);
    });

    test('an ink-free tile owes nothing once it has been scanned', () {
      final blank = BitmapTile.blank(size: tileSize);
      expect(blank.inkBoundsKnown, isFalse);

      expect(
        bitmapSurfaceContentBounds(
          BitmapSurface(
            canvasSize: const CanvasSize(
              width: 2 * tileSize,
              height: 2 * tileSize,
            ),
            tileSize: tileSize,
            tiles: {TileCoord(x: 0, y: 0): blank},
          ),
        ),
        isNull,
      );

      expect(blank.inkBoundsKnown, isTrue);
      expect(blank.hasInk, isFalse);
      expect(blank.inkBounds, isNull);
    });

    test('a tile that does not know its box is asked of the engine, every '
        'one of them, and a tile that knows is not', () {
      final (one, other) = (
        tileWithInk(TileCoord(x: 0, y: 0), [(x: 2, y: 1)]).tile,
        tileWithInk(TileCoord(x: 1, y: 0), [(x: 3, y: 2)]).tile,
      );
      final known = tileWithInk(TileCoord(x: 2, y: 0), [(x: 4, y: 3)]).tile
        ..rememberInkBounds((
          left: 4,
          top: 3,
          rightExclusive: 5,
          bottomExclusive: 4,
        ));

      final bounds = bitmapSurfaceContentBounds(
        BitmapSurface(
          canvasSize: const CanvasSize(
            width: 3 * tileSize,
            height: 3 * tileSize,
          ),
          tileSize: tileSize,
          tiles: {
            TileCoord(x: 0, y: 0): one,
            TileCoord(x: 1, y: 0): other,
            TileCoord(x: 2, y: 0): known,
          },
        ),
      )!;

      expect(bounds.left, 2);
      expect(bounds.rightExclusive, 2 * tileSize + 5);
      final ledger = EngineTileLedger.instance;
      expect(ledger.slotOf(one), isNotNull);
      expect(ledger.slotOf(other), isNotNull);
      expect(ledger.slotOf(known), isNull);
    });
  });
}
