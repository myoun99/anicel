import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_pixel_blend_operation.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_operation_apply.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';

void main() {
  final transparent = RgbaColor(r: 0, g: 0, b: 0, a: 0);
  final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
  final green = RgbaColor(r: 0, g: 255, b: 0, a: 128);
  final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);
  final purple = RgbaColor(r: 128, g: 0, b: 128, a: 255);
  final rgbaOrderColor = RgbaColor(r: 1, g: 2, b: 3, a: 4);

  BitmapTile blankTile({int tileX = 0, int tileY = 0, int size = 2}) {
    return BitmapTile.blank(
      coord: TileCoord(x: tileX, y: tileY),
      size: size,
    );
  }

  BrushPixelBlendOperation op({
    required int x,
    required int y,
    required RgbaColor before,
    required RgbaColor after,
  }) {
    return BrushPixelBlendOperation(x: x, y: y, before: before, after: after);
  }

  group('applyBrushPixelBlendOperationsToBitmapTile', () {
    test('returns original tile when operations is empty', () {
      final tile = blankTile();

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: const [],
      );

      expect(identical(result, tile), isTrue);
    });

    test('returns original tile when no operation affects tile', () {
      final tile = blankTile(size: 2);

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 2, y: 0, before: transparent, after: red)],
      );

      expect(identical(result, tile), isTrue);
    });

    test('applies one operation inside tile', () {
      final tile = blankTile();

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 1, y: 0, before: transparent, after: red)],
      );

      expect(identical(result, tile), isFalse);
      expect(readRgbaColorFromBitmapTile(tile: result, x: 1, y: 0), red);
      expect(readRgbaColorFromBitmapTile(tile: tile, x: 1, y: 0), transparent);
    });

    test('maps global coordinates to local tile coordinates', () {
      final tile = blankTile(tileX: 2, tileY: 3, size: 4);

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 8, y: 12, before: transparent, after: red)],
      );

      expect(readRgbaColorFromBitmapTile(tile: result, x: 0, y: 0), red);
    });

    test('does not treat operation coordinates as local coordinates', () {
      final tile = blankTile(tileX: 2, tileY: 3, size: 4);

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 8, y: 12, before: transparent, after: blue)],
      );

      expect(readRgbaColorFromBitmapTile(tile: result, x: 0, y: 0), blue);
    });

    test('ignores operations outside tile', () {
      final tile = blankTile(tileX: 1, tileY: 1, size: 2);

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [
          op(x: 1, y: 2, before: transparent, after: red),
          op(x: 2, y: 1, before: transparent, after: red),
          op(x: 4, y: 2, before: transparent, after: red),
          op(x: 2, y: 4, before: transparent, after: red),
          op(x: 3, y: 3, before: transparent, after: blue),
        ],
      );

      expect(readRgbaColorFromBitmapTile(tile: result, x: 1, y: 1), blue);
      expect(
        readRgbaColorFromBitmapTile(tile: result, x: 0, y: 0),
        transparent,
      );
      expect(
        readRgbaColorFromBitmapTile(tile: result, x: 1, y: 0),
        transparent,
      );
      expect(
        readRgbaColorFromBitmapTile(tile: result, x: 0, y: 1),
        transparent,
      );
    });

    test('applies multiple operations in provided order', () {
      final tile = blankTile(size: 3);

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [
          op(x: 2, y: 2, before: transparent, after: red),
          op(x: 0, y: 0, before: transparent, after: blue),
          op(x: 1, y: 1, before: transparent, after: purple),
        ],
      );

      expect(readRgbaColorFromBitmapTile(tile: result, x: 2, y: 2), red);
      expect(readRgbaColorFromBitmapTile(tile: result, x: 0, y: 0), blue);
      expect(readRgbaColorFromBitmapTile(tile: result, x: 1, y: 1), purple);
    });

    test('applies repeated same-pixel operations using working buffer', () {
      final tile = blankTile();

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [
          op(x: 0, y: 0, before: transparent, after: red),
          op(x: 0, y: 0, before: red, after: blue),
        ],
      );

      expect(readRgbaColorFromBitmapTile(tile: result, x: 0, y: 0), blue);
    });

    test(
      'throws StateError when operation.before does not match current tile pixel',
      () {
        final tile = blankTile();

        expect(
          () => applyBrushPixelBlendOperationsToBitmapTile(
            tile: tile,
            operations: [op(x: 0, y: 0, before: red, after: blue)],
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('does not mutate original tile', () {
      final tile = blankTile();
      final originalPixels = tile.pixels;

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 1, y: 0, before: transparent, after: red)],
      );

      expect(tile.pixels, originalPixels);
      expect(readRgbaColorFromBitmapTile(tile: tile, x: 1, y: 0), transparent);
      expect(readRgbaColorFromBitmapTile(tile: result, x: 1, y: 0), red);
    });

    test('preserves tile coord', () {
      final coord = TileCoord(x: 3, y: 4);
      final tile = BitmapTile.blank(coord: coord, size: 2);

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 6, y: 8, before: transparent, after: red)],
      );

      expect(result.coord, coord);
    });

    test('preserves tile size', () {
      final tile = blankTile(tileX: 3, tileY: 4, size: 2);

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 6, y: 8, before: transparent, after: red)],
      );

      expect(result.size, 2);
    });

    test('only changes targeted pixels', () {
      final tile = blankTile();

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [op(x: 1, y: 0, before: transparent, after: green)],
      );

      expect(
        readRgbaColorFromBitmapTile(tile: result, x: 0, y: 0),
        transparent,
      );
      expect(readRgbaColorFromBitmapTile(tile: result, x: 1, y: 0), green);
      expect(
        readRgbaColorFromBitmapTile(tile: result, x: 0, y: 1),
        transparent,
      );
      expect(
        readRgbaColorFromBitmapTile(tile: result, x: 1, y: 1),
        transparent,
      );
    });

    test('uses RGBA byte order through RgbaColor', () {
      final tile = blankTile();

      final result = applyBrushPixelBlendOperationsToBitmapTile(
        tile: tile,
        operations: [
          op(x: 0, y: 1, before: transparent, after: rgbaOrderColor),
        ],
      );

      expect(result.pixels.sublist(8, 12), [1, 2, 3, 4]);
      expect(
        readRgbaColorFromBitmapTile(tile: result, x: 0, y: 1),
        rgbaOrderColor,
      );
    });
  });
}
