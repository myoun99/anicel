import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('BitmapSurface', () {
    BitmapSurface surface({Map<TileCoord, BitmapTile> tiles = const {}}) =>
        BitmapSurface(
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          tiles: tiles,
        );

    test(
      'empty surface stores no tiles',
      () => expect(surface().tiles, isEmpty),
    );
    test('default tileSize is 256', () => expect(surface().tileSize, 256));
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

    test('putTile inserts a tile', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256);
      expect(surface().putTile(tile).tileAt(tile.coord), tile);
    });

    test('putTile replaces existing tile', () {
      final coord = TileCoord(x: 0, y: 0);
      final first = BitmapTile.blank(coord: coord, size: 256);
      final second = BitmapTile(
        coord: coord,
        size: 256,
        pixels: Uint8List(256 * 256 * 4)..[0] = 9,
      );
      final next = surface().putTile(first).putTile(second);
      expect(next.tileAt(coord), second);
    });

    test('putTile does not mutate original surface', () {
      final original = surface();
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256);
      final next = original.putTile(tile);
      expect(original.tileAt(tile.coord), isNull);
      expect(next.tileAt(tile.coord), tile);
    });

    test('removeTile removes a tile', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256);
      expect(
        surface().putTile(tile).removeTile(tile.coord).tileAt(tile.coord),
        isNull,
      );
    });

    test('removeTile does not mutate original surface', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256);
      final original = surface().putTile(tile);
      final next = original.removeTile(tile.coord);
      expect(original.tileAt(tile.coord), tile);
      expect(next.tileAt(tile.coord), isNull);
    });

    test('constructor rejects tile whose coord does not match map key', () {
      expect(
        () => surface(
          tiles: {
            TileCoord(x: 1, y: 0): BitmapTile.blank(
              coord: TileCoord(x: 0, y: 0),
              size: 256,
            ),
          },
        ),
        throwsArgumentError,
      );
    });

    test('constructor rejects tile with wrong size', () {
      expect(
        () => surface(
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile.blank(
              coord: TileCoord(x: 0, y: 0),
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
              coord: TileCoord(x: 23, y: 0),
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
              coord: TileCoord(x: -16, y: 0),
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
        final firstTile = BitmapTile.blank(coord: firstCoord, size: 256);
        final secondTile = BitmapTile(
          coord: secondCoord,
          size: 256,
          pixels: Uint8List(256 * 256 * 4)..[0] = 3,
        );

        final firstSurface = surface().putTile(firstTile).putTile(secondTile);
        final secondSurface = surface().putTile(secondTile).putTile(firstTile);

        expect(firstSurface, secondSurface);
        expect(firstSurface.hashCode, secondSurface.hashCode);
      },
    );

    test('toJson/fromJson round-trips', () {
      final tile = BitmapTile(
        coord: TileCoord(x: 1, y: 2),
        size: 256,
        pixels: Uint8List(256 * 256 * 4)..[0] = 7,
      );
      final original = surface().putTile(tile);
      expectJsonRoundTrip(original, BitmapSurface.fromJson);
    });

    test('surface does not allocate all possible tiles eagerly', () {
      final empty = surface();
      expect(empty.tileCount, 40);
      expect(empty.tiles.length, 0);
    });
  });
}
