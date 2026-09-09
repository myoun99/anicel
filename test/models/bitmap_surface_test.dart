import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('BitmapSurface', () {
    /// ⚠️**THE TILE SIZE IS STATED, not taken from the default.** Every
    /// case below is about the surface's ARITHMETIC — ceiling division,
    /// the pasteboard's bounds, which coords are storable — and those
    /// answers are derived from a tile size, not from THE tile size. Left
    /// on the default they all moved the day it did (2026-09-09, 256 →
    /// 128), which would have said the arithmetic broke when only the
    /// input had changed. What the default IS gets its own case below.
    BitmapSurface surface({Map<TileCoord, BitmapTile> tiles = const {}}) =>
        BitmapSurface(
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          tileSize: 256,
          tiles: tiles,
        );

    test(
      'empty surface stores no tiles',
      () => expect(surface().tiles, isEmpty),
    );

    /// 🚨★★★**THE ONE PLACE THE VALUE ITSELF IS PINNED.** It was written
    /// in eight files — the surface, the edit-session store, the display
    /// cache service, the live stroke rasterizer, the stroke overlay and
    /// three import paths — each with its own `256` default, and NOT ONE
    /// caller passes a tile size, so they agreed only by everybody having
    /// typed the same number. A surface at one size with an overlay at
    /// another is not a slow path, it is wrong pixels.
    ///
    /// 유저 확정 2026-09-09: 「128로 통일해서 가자」. Measured: 128 is the
    /// fastest of the three on commit and on decode, holds a third of 256's
    /// undo bytes, and pays 2x its paint — where 64 pays 6.2x.
    test('the default is 128, and every default reads THIS constant', () {
      expect(defaultCelTileSize, 128);
      expect(
        BitmapSurface(canvasSize: const CanvasSize(width: 1920, height: 1080))
            .tileSize,
        defaultCelTileSize,
      );
    });
    test(
      'tileColumnCount uses ceiling division',
      () => expect(surface().tileColumnCount, 8),
    );
    test(
      'tileRowCount uses ceiling division',
      () => expect(surface().tileRowCount, 5),
    );
    test('tileCount is columns * rows', () => expect(surface().tileCount, 40));

    test(
      'containsTileCoord returns true for valid coords',
      () => expect(surface().containsTileCoord(TileCoord(x: 7, y: 4)), isTrue),
    );
    // Pasteboard (3×3 — ONE canvas size each side, H2 유저 확정
    // 2026-08-22): x ∈ [-1920, 3840) → tiles [-8, 15), y ∈ [-1080, 2160)
    // → tiles [-5, 9).
    test(
      'containsTileCoord accepts pasteboard tiles beyond the canvas grid',
      () {
        expect(surface().containsTileCoord(TileCoord(x: 8, y: 4)), isTrue);
        expect(surface().containsTileCoord(TileCoord(x: 14, y: 8)), isTrue);
        expect(surface().containsTileCoord(TileCoord(x: -8, y: -5)), isTrue);
      },
    );
    test(
      'containsTileCoord returns false for coord outside pasteboard right edge',
      () =>
          expect(surface().containsTileCoord(TileCoord(x: 15, y: 4)), isFalse),
    );
    test(
      'containsTileCoord returns false for coord outside pasteboard bottom '
      'edge',
      () =>
          expect(surface().containsTileCoord(TileCoord(x: 7, y: 9)), isFalse),
    );
    test(
      'tileAt returns null for missing tile',
      () => expect(surface().tileAt(TileCoord(x: 0, y: 0)), isNull),
    );

    test('putTiles inserts a tile', () {
      final tile = BitmapTile.blank(size: 256);
      expect(surface().putTiles([(coord: TileCoord(x: 0, y: 0), tile: tile)]).tileAt(TileCoord(x: 0, y: 0)), tile);
    });

    test('putTiles replaces existing tile', () {
      final coord = TileCoord(x: 0, y: 0);
      final first = BitmapTile.blank(size: 256);
      final second = BitmapTile(
        size: 256,
        pixels: Uint8List(256 * 256 * 4)..[0] = 9,
      );
      expect(
        surface().putTiles([(coord: coord, tile: first)]).putTiles([(coord: coord, tile: second)]).tileAt(coord),
        second,
      );
      // The later tile of one batch wins too — the batch is a sequence of
      // puts, not a set of them.
      expect(surface().putTiles([(coord: coord, tile: first), (coord: coord, tile: second)]).tileAt(coord), second);
    });

    test('putTiles does not mutate original surface', () {
      final original = surface();
      final tile = BitmapTile.blank(size: 256);
      final next = original.putTiles([(coord: TileCoord(x: 0, y: 0), tile: tile)]);
      expect(original.tileAt(TileCoord(x: 0, y: 0)), isNull);
      expect(next.tileAt(TileCoord(x: 0, y: 0)), tile);
    });

    test('putTiles rejects a coord outside the pasteboard', () {
      expect(
        () => surface().putTiles([
          (coord: TileCoord(x: 23, y: 0), tile: BitmapTile.blank(size: 256)),
        ]),
        throwsArgumentError,
      );
      expect(
        () => surface().putTiles([
          (coord: TileCoord(x: -16, y: 0), tile: BitmapTile.blank(size: 256)),
        ]),
        throwsArgumentError,
      );
    });


    test('putTiles rejects a tile whose size is not the surface tile size', () {
      expect(
        () => surface().putTiles([
          (coord: TileCoord(x: 0, y: 0), tile: BitmapTile.blank(size: 128)),
        ]),
        throwsArgumentError,
      );
    });
    test('a rejected tile takes the whole batch with it', () {
      final good = BitmapTile.blank(size: 256);
      final bad = BitmapTile.blank(size: 256);
      final original = surface();
      expect(() => original.putTiles([(coord: TileCoord(x: 0, y: 0), tile: good), (coord: TileCoord(x: 23, y: 0), tile: bad)]), throwsArgumentError);
      expect(original.tileAt(TileCoord(x: 0, y: 0)), isNull);
    });

    /// 🪦**`removeTile` IS GONE AND SO ARE ITS CASES.** Nothing in lib
    /// ever called it. A surface does lose tiles — through
    /// `putMaterializedTiles`, which drops one whose ink is gone as
    /// part of the pass that emptied it, and through
    /// `resizeBitmapSurfaceCanvas`, which drops what falls outside the
    /// new pasteboard. Both are covered where they happen.


    /// 🪦**「constructor rejects tile whose coord does not match map key」**
    /// **IS GONE BECAUSE THE STATE IS.** A tile carried its own
    /// coordinate, so a tile stored under a key it disagreed with was
    /// writable and had to be refused at runtime. A tile has no
    /// coordinate now — the map key is the only place a tile's place is
    /// written — so the disagreement cannot be spelled and there is
    /// nothing left to refuse. The size and bounds checks below are the
    /// two the constructor still has.

    test('constructor rejects tile with wrong size', () {
      expect(
        () => surface(
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile.blank(
              size: 128,
            ),
          },
        ),
        throwsArgumentError,
      );
    });

    test('constructor rejects tile outside pasteboard bounds', () {
      expect(
        () => surface(
          tiles: {
            TileCoord(x: 23, y: 0): BitmapTile.blank(
              size: 256,
            ),
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => surface(
          tiles: {
            TileCoord(x: -16, y: 0): BitmapTile.blank(
              size: 256,
            ),
          },
        ),
        throwsArgumentError,
      );
    });

    test(
      'same tiles in different insertion orders are equal and share hashCode',
      () {
        final firstCoord = TileCoord(x: 0, y: 0);
        final secondCoord = TileCoord(x: 1, y: 0);
        final firstTile = BitmapTile.blank(size: 256);
        final secondTile = BitmapTile(
          size: 256,
          pixels: Uint8List(256 * 256 * 4)..[0] = 3,
        );

        final firstSurface = surface().putTiles([(coord: firstCoord, tile: firstTile), (coord: secondCoord, tile: secondTile)]);
        final secondSurface = surface().putTiles([(coord: secondCoord, tile: secondTile), (coord: firstCoord, tile: firstTile)]);

        expect(firstSurface, secondSurface);
        expect(firstSurface.hashCode, secondSurface.hashCode);
      },
    );

    test('toJson/fromJson round-trips', () {
      final tile = BitmapTile(
        size: 256,
        pixels: Uint8List(256 * 256 * 4)..[0] = 7,
      );
      final original = surface().putTiles([(coord: TileCoord(x: 1, y: 2), tile: tile)]);
      expectJsonRoundTrip(original, BitmapSurface.fromJson);
    });

    test('surface does not allocate all possible tiles eagerly', () {
      final empty = surface();
      expect(empty.tileCount, 40);
      expect(empty.tiles.length, 0);
    });

    /// 🚨★★★**THE GETTER COPIED THE WHOLE MAP ON EVERY READ.** It was
    /// `Map.unmodifiable(_tiles)`, which the SDK documents as behaving like
    /// `Map.from` — a full rebuild per call, on a getter read by roughly
    /// thirty callers, several of them per commit and per frame. Nothing
    /// BEHAVIOURAL could see it: a copy and a view answer every question
    /// identically. Identity can, and identity is exactly the property that
    /// makes it free.
    test('🚨reading the tiles twice hands back the SAME map, not a copy', () {
      final coord = TileCoord(x: 0, y: 0);
      final built = surface(
        tiles: {
          coord: BitmapTile(
            size: 256,
            pixels: Uint8List(BitmapTile.bytesFor(256)),
          ),
        },
      );

      expect(identical(built.tiles, built.tiles), isTrue);
      // And a derived surface keeps the property — that constructor wraps
      // rather than copies, which is the half that had to change.
      final grown = built.putTiles([
        (
          coord: TileCoord(x: 1, y: 0),
          tile: BitmapTile(
            size: 256,
            pixels: Uint8List(BitmapTile.bytesFor(256)),
          ),
        ),
      ]);
      expect(identical(grown.tiles, grown.tiles), isTrue);
    });

    test('and it is still unmodifiable from the outside', () {
      final built = surface();
      expect(
        () => built.tiles[TileCoord(x: 9, y: 9)] = BitmapTile.blank(
          size: 256,
        ),
        throwsUnsupportedError,
      );
    });
  });
}
