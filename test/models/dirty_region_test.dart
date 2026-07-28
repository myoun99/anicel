import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('DirtyRegion', () {
    test('creates from left/top/rightExclusive/bottomExclusive', () {
      final region = DirtyRegion.fromLTBR(
        left: 1,
        top: 2,
        rightExclusive: 3,
        bottomExclusive: 4,
      );
      expect(region.left, 1);
      expect(region.top, 2);
      expect(region.rightExclusive, 3);
      expect(region.bottomExclusive, 4);
    });

    test('creates from x/y/width/height', () {
      final region = DirtyRegion.fromXYWH(x: 1, y: 2, width: 3, height: 4);
      expect(region.left, 1);
      expect(region.top, 2);
      expect(region.rightExclusive, 4);
      expect(region.bottomExclusive, 6);
    });

    test('width returns rightExclusive - left', () {
      expect(
        DirtyRegion.fromLTBR(
          left: 2,
          top: 0,
          rightExclusive: 7,
          bottomExclusive: 1,
        ).width,
        5,
      );
    });

    test('height returns bottomExclusive - top', () {
      expect(
        DirtyRegion.fromLTBR(
          left: 0,
          top: 2,
          rightExclusive: 1,
          bottomExclusive: 7,
        ).height,
        5,
      );
    });

    test('negative left/top are allowed (pasteboard space)', () {
      final region = DirtyRegion(
        left: -300,
        top: -10,
        rightExclusive: 1,
        bottomExclusive: 1,
      );
      expect(region.left, -300);
      expect(region.top, -10);
      expect(region.width, 301);
      expect(region.height, 11);
    });

    test('toTileCoords floor-divides negative coordinates', () {
      final region = DirtyRegion(
        left: -1,
        top: -257,
        rightExclusive: 1,
        bottomExclusive: 1,
      );
      final coords = region.toTileCoords(tileSize: 256);
      expect(
        coords,
        containsAll([
          TileCoord(x: -1, y: -2),
          TileCoord(x: -1, y: -1),
          TileCoord(x: -1, y: 0),
          TileCoord(x: 0, y: -2),
          TileCoord(x: 0, y: -1),
          TileCoord(x: 0, y: 0),
        ]),
      );
      expect(coords.length, 6);
    });

    test('rightExclusive <= left throws', () {
      expect(
        () =>
            DirtyRegion(left: 1, top: 0, rightExclusive: 1, bottomExclusive: 1),
        throwsArgumentError,
      );
      expect(
        () =>
            DirtyRegion(left: 1, top: 0, rightExclusive: 0, bottomExclusive: 1),
        throwsArgumentError,
      );
    });

    test('bottomExclusive <= top throws', () {
      expect(
        () =>
            DirtyRegion(left: 0, top: 1, rightExclusive: 1, bottomExclusive: 1),
        throwsArgumentError,
      );
      expect(
        () =>
            DirtyRegion(left: 0, top: 1, rightExclusive: 1, bottomExclusive: 0),
        throwsArgumentError,
      );
    });

    test('fromXYWH accepts negative x/y (pasteboard space)', () {
      final region = DirtyRegion.fromXYWH(x: -5, y: -7, width: 2, height: 3);
      expect(region.left, -5);
      expect(region.top, -7);
      expect(region.rightExclusive, -3);
      expect(region.bottomExclusive, -4);
    });

    test('fromXYWH rejects zero width', () {
      expect(
        () => DirtyRegion.fromXYWH(x: 0, y: 0, width: 0, height: 1),
        throwsArgumentError,
      );
    });

    test('fromXYWH rejects zero height', () {
      expect(
        () => DirtyRegion.fromXYWH(x: 0, y: 0, width: 1, height: 0),
        throwsArgumentError,
      );
    });

    test('fromXYWH rejects negative width', () {
      expect(
        () => DirtyRegion.fromXYWH(x: 0, y: 0, width: -1, height: 1),
        throwsArgumentError,
      );
    });

    test('fromXYWH rejects negative height', () {
      expect(
        () => DirtyRegion.fromXYWH(x: 0, y: 0, width: 1, height: -1),
        throwsArgumentError,
      );
    });

    test('copyWith updates fields', () {
      expect(
        DirtyRegion(
          left: 1,
          top: 2,
          rightExclusive: 3,
          bottomExclusive: 4,
        ).copyWith(left: 5, top: 6, rightExclusive: 7, bottomExclusive: 8),
        DirtyRegion(left: 5, top: 6, rightExclusive: 7, bottomExclusive: 8),
      );
    });

    test('equality includes all bounds', () {
      final region = DirtyRegion(
        left: 1,
        top: 2,
        rightExclusive: 3,
        bottomExclusive: 4,
      );
      expect(
        region,
        DirtyRegion(left: 1, top: 2, rightExclusive: 3, bottomExclusive: 4),
      );
      expect(
        region,
        isNot(
          DirtyRegion(left: 0, top: 2, rightExclusive: 3, bottomExclusive: 4),
        ),
      );
      expect(
        region,
        isNot(
          DirtyRegion(left: 1, top: 0, rightExclusive: 3, bottomExclusive: 4),
        ),
      );
      expect(
        region,
        isNot(
          DirtyRegion(left: 1, top: 2, rightExclusive: 4, bottomExclusive: 4),
        ),
      );
      expect(
        region,
        isNot(
          DirtyRegion(left: 1, top: 2, rightExclusive: 3, bottomExclusive: 5),
        ),
      );
    });

    test('toJson/fromJson round-trips', () {
      final region = DirtyRegion(
        left: 1,
        top: 2,
        rightExclusive: 3,
        bottomExclusive: 4,
      );
      expectJsonRoundTrip(region, DirtyRegion.fromJson);
    });

    test('containsPixel is true inside region', () {
      expect(
        DirtyRegion(
          left: 1,
          top: 2,
          rightExclusive: 4,
          bottomExclusive: 5,
        ).containsPixel(x: 3, y: 4),
        isTrue,
      );
    });

    test('containsPixel is false at rightExclusive', () {
      expect(
        DirtyRegion(
          left: 1,
          top: 2,
          rightExclusive: 4,
          bottomExclusive: 5,
        ).containsPixel(x: 4, y: 4),
        isFalse,
      );
    });

    test('containsPixel is false at bottomExclusive', () {
      expect(
        DirtyRegion(
          left: 1,
          top: 2,
          rightExclusive: 4,
          bottomExclusive: 5,
        ).containsPixel(x: 3, y: 5),
        isFalse,
      );
    });

    test('intersects returns true for overlapping regions', () {
      expect(
        DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 10,
          bottomExclusive: 10,
        ).intersects(
          DirtyRegion(left: 9, top: 9, rightExclusive: 11, bottomExclusive: 11),
        ),
        isTrue,
      );
    });

    test(
      'intersects returns false for touching but non-overlapping regions',
      () {
        expect(
          DirtyRegion(
            left: 0,
            top: 0,
            rightExclusive: 10,
            bottomExclusive: 10,
          ).intersects(
            DirtyRegion(
              left: 10,
              top: 0,
              rightExclusive: 11,
              bottomExclusive: 10,
            ),
          ),
          isFalse,
        );
      },
    );

    test('union returns bounding region', () {
      expect(
        DirtyRegion(
          left: 2,
          top: 3,
          rightExclusive: 5,
          bottomExclusive: 6,
        ).union(
          DirtyRegion(left: 1, top: 4, rightExclusive: 7, bottomExclusive: 5),
        ),
        DirtyRegion(left: 1, top: 3, rightExclusive: 7, bottomExclusive: 6),
      );
    });

    test('toTileCoords returns one tile for region fully inside one tile', () {
      expect(
        DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 1,
          bottomExclusive: 1,
        ).toTileCoords(tileSize: 256),
        {TileCoord(x: 0, y: 0)},
      );
    });

    test('toTileCoords returns two horizontal tiles across tile boundary', () {
      expect(
        DirtyRegion(
          left: 255,
          top: 0,
          rightExclusive: 257,
          bottomExclusive: 1,
        ).toTileCoords(tileSize: 256),
        {TileCoord(x: 0, y: 0), TileCoord(x: 1, y: 0)},
      );
    });

    test('toTileCoords returns two vertical tiles across tile boundary', () {
      expect(
        DirtyRegion(
          left: 0,
          top: 255,
          rightExclusive: 1,
          bottomExclusive: 257,
        ).toTileCoords(tileSize: 256),
        {TileCoord(x: 0, y: 0), TileCoord(x: 0, y: 1)},
      );
    });

    test('toTileCoords returns four tiles across both boundaries', () {
      expect(
        DirtyRegion(
          left: 255,
          top: 255,
          rightExclusive: 257,
          bottomExclusive: 257,
        ).toTileCoords(tileSize: 256),
        {
          TileCoord(x: 0, y: 0),
          TileCoord(x: 1, y: 0),
          TileCoord(x: 0, y: 1),
          TileCoord(x: 1, y: 1),
        },
      );
    });

    test('toTileCoords rejects zero tileSize', () {
      expect(
        () => DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 1,
          bottomExclusive: 1,
        ).toTileCoords(tileSize: 0),
        throwsArgumentError,
      );
    });

    test('toTileCoords rejects negative tileSize', () {
      expect(
        () => DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 1,
          bottomExclusive: 1,
        ).toTileCoords(tileSize: -1),
        throwsArgumentError,
      );
    });

    test(
      'toTileCoords produces coords compatible with BitmapSurface bounds checks',
      () {
        final surface = BitmapSurface(
          canvasSize: const CanvasSize(width: 512, height: 512),
        );
        final coords = DirtyRegion(
          left: 255,
          top: 255,
          rightExclusive: 257,
          bottomExclusive: 257,
        ).toTileCoords(tileSize: surface.tileSize);
        expect(coords.every(surface.containsTileCoord), isTrue);
      },
    );
  });
}
