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
}
