import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('TileCoord', () {


    test('negative coords are allowed (pasteboard tiles)', () {
      final coord = TileCoord(x: -3, y: -1);
      expect(coord.x, -3);
      expect(coord.y, -1);
      expectJsonRoundTrip(coord, TileCoord.fromJson);
    });

    test('copyWith updates x', () {
      final coord = TileCoord(x: 1, y: 2);
      expect(coord.copyWith(x: 3).x, 3);
      expect(coord.x, 1);
    });

    test('copyWith updates y', () {
      final coord = TileCoord(x: 1, y: 2);
      expect(coord.copyWith(y: 4).y, 4);
      expect(coord.y, 2);
    });

    test('equality includes x and y', () {
      final coord = TileCoord(x: 1, y: 2);
      expect(coord, TileCoord(x: 1, y: 2));
      expect(coord.copyWith(x: 9), isNot(coord));
      expect(coord.copyWith(y: 9), isNot(coord));
    });

    test('toJson/fromJson round-trips', () {
      final coord = TileCoord(x: 3, y: 4);
      expect(TileCoord.fromJson(coord.toJson()), coord);
    });

    test('fromPixel maps pixel coordinate to tile coordinate', () {
      expect(
        TileCoord.fromPixel(pixelX: 0, pixelY: 0, tileSize: 256),
        TileCoord(x: 0, y: 0),
      );
      expect(
        TileCoord.fromPixel(pixelX: 255, pixelY: 255, tileSize: 256),
        TileCoord(x: 0, y: 0),
      );
      expect(
        TileCoord.fromPixel(pixelX: 511, pixelY: 10, tileSize: 256),
        TileCoord(x: 1, y: 0),
      );
    });

    test('fromPixel handles boundary exactly at tile size', () {
      expect(
        TileCoord.fromPixel(pixelX: 256, pixelY: 256, tileSize: 256),
        TileCoord(x: 1, y: 1),
      );
    });

    test('fromPixel floor-divides negative pixels (pasteboard space)', () {
      expect(
        TileCoord.fromPixel(pixelX: -1, pixelY: -1, tileSize: 256),
        TileCoord(x: -1, y: -1),
      );
      expect(
        TileCoord.fromPixel(pixelX: -256, pixelY: -257, tileSize: 256),
        TileCoord(x: -1, y: -2),
      );
    });
    test(
      'fromPixel rejects zero tileSize',
      () => expect(
        () => TileCoord.fromPixel(pixelX: 0, pixelY: 0, tileSize: 0),
        throwsArgumentError,
      ),
    );
    test(
      'fromPixel rejects negative tileSize',
      () => expect(
        () => TileCoord.fromPixel(pixelX: 0, pixelY: 0, tileSize: -1),
        throwsArgumentError,
      ),
    );
  });

  // The ONE tile-range law (round 8 of the audit): every walk over "the
  // tiles a rect touches" reads its box from here, so the floorDiv that
  // keeps pasteboard tiles right cannot be lost by one of them.
  group('tileRangeOf', () {
    test('floor-divides NEGATIVE (pasteboard) edges, never truncates', () {
      // A rect straddling the canvas origin: pixel -1 is tile -1, not 0.
      final range = tileRangeOf(
        left: -1,
        top: -1,
        rightExclusive: 1,
        bottomExclusive: 1,
        tileSize: 256,
      );
      expect(range, (firstX: -1, lastX: 0, firstY: -1, lastY: 0));
    });

    test('the exclusive edge on a tile boundary does NOT reach the next '
        'tile', () {
      expect(
        tileRangeOf(
          left: 0,
          top: 0,
          rightExclusive: 256,
          bottomExclusive: 512,
          tileSize: 256,
        ),
        (firstX: 0, lastX: 0, firstY: 0, lastY: 1),
      );
      expect(
        tileRangeOf(
          left: 0,
          top: 0,
          rightExclusive: 257,
          bottomExclusive: 513,
          tileSize: 256,
        ),
        (firstX: 0, lastX: 1, firstY: 0, lastY: 2),
      );
    });

    test('a one-pixel rect deep in a tile is that tile alone', () {
      expect(
        tileRangeOf(
          left: 300,
          top: 700,
          rightExclusive: 301,
          bottomExclusive: 701,
          tileSize: 256,
        ),
        (firstX: 1, lastX: 1, firstY: 2, lastY: 2),
      );
    });
  });

  group('tileRangeCovering', () {
    test('is tileRangeOf over the floor/ceil lattice of the double rect', () {
      // 0.5..256.0 covers pixels 0..255 — ONE tile; 256.2 spills into the
      // next; -0.5 floors to pixel -1, the tile at -1.
      expect(
        tileRangeCovering(
          left: 0.5,
          top: -0.5,
          right: 256.0,
          bottom: 256.2,
          tileSize: 256,
        ),
        tileRangeOf(
          left: 0,
          top: -1,
          rightExclusive: 256,
          bottomExclusive: 257,
          tileSize: 256,
        ),
      );
      expect(
        tileRangeCovering(
          left: 0.5,
          top: -0.5,
          right: 256.0,
          bottom: 256.2,
          tileSize: 256,
        ),
        (firstX: 0, lastX: 0, firstY: -1, lastY: 1),
      );
    });
  });

  group('tileCoordsIn', () {
    test('walks the box ROW-MAJOR: tile row outer, column inner', () {
      expect(
        tileCoordsIn((firstX: -1, lastX: 0, firstY: 2, lastY: 3)),
        [
          TileCoord(x: -1, y: 2),
          TileCoord(x: 0, y: 2),
          TileCoord(x: -1, y: 3),
          TileCoord(x: 0, y: 3),
        ],
      );
    });

    test('a single-tile box is one coordinate', () {
      expect(
        tileCoordsIn((firstX: 4, lastX: 4, firstY: 4, lastY: 4)),
        [TileCoord(x: 4, y: 4)],
      );
    });
  });
}
