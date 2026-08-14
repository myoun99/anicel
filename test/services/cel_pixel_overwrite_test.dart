import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';

/// One pixel a walk visits: tile, tile-local x/y, and mask coverage.
typedef _Pixel = (TileCoord coord, int x, int y, int mask);

void main() {
  const canvas = CanvasSize(width: 512, height: 512);
  final origin = TileCoord(x: 0, y: 0);
  final neighbour = TileCoord(x: 1, y: 0);

  /// A tile whose pixel (x, y) carries [rgba], everything else transparent.
  BitmapTile tileWith(
    TileCoord coord,
    Map<(int, int), List<int>> pixels,
  ) {
    final bytes = Uint8List(256 * 256 * 4);
    for (final entry in pixels.entries) {
      final offset = ((entry.key.$2 * 256) + entry.key.$1) * 4;
      bytes.setRange(offset, offset + 4, entry.value);
    }
    return BitmapTile(coord: coord, size: 256, pixels: bytes);
  }

  BitmapSurface surfaceOf(Iterable<BitmapTile> tiles) => BitmapSurface(
    canvasSize: canvas,
    tiles: {for (final tile in tiles) tile.coord: tile},
  );

  List<int> pixelAt(BitmapSurface surface, TileCoord coord, int x, int y) {
    final tile = surface.tileAt(coord)!;
    final offset = ((y * 256) + x) * 4;
    return tile.readPixels(
      (_, view) => List<int>.from(view.sublist(offset, offset + 4)),
    );
  }

  CelPixelWalk walk(List<_Pixel> pixels) => (visit) {
    for (final pixel in pixels) {
      visit(pixel.$1, pixel.$2, pixel.$3, pixel.$4);
    }
  };

  group('colour channel (색 변환)', () {
    test('replaces RGB and leaves alpha exactly as it was', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [0, 0, 0, 255],
          (1, 0): [0, 0, 0, 90],
        }),
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, 0, 0, 255), (origin, 1, 0, 255)]),
        value: Uint8List.fromList([255, 0, 0]),
      );

      expect(pixelAt(result.surface, origin, 0, 0), [255, 0, 0, 255]);
      // The anti-aliased edge pixel keeps its coverage — that is the
      // drawing's shape, and this verb never touches shape.
      expect(pixelAt(result.surface, origin, 1, 0), [255, 0, 0, 90]);
    });

    test('skips fully transparent pixels', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [0, 0, 0, 0],
        }),
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, 0, 0, 255)]),
        value: Uint8List.fromList([255, 0, 0]),
      );

      // Nothing participated, so nothing was rebuilt at all.
      expect(result.restore, isNull);
      expect(identical(result.surface, surface), isTrue);
    });

    test('flat line art yields a three-byte recipe', () {
      final surface = surfaceOf([
        tileWith(origin, {
          for (var x = 0; x < 40; x += 1) (x, 0): [17, 17, 17, 255],
        }),
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([for (var x = 0; x < 40; x += 1) (origin, x, 0, 255)]),
        value: Uint8List.fromList([200, 30, 30]),
      );

      final restore = result.restore;
      expect(restore, isA<UniformCelPixelRestore>());
      expect((restore! as UniformCelPixelRestore).value, [17, 17, 17]);
      expect(restore.estimatedRetainedBytes, 3);
    });

    test('undo restores the original bytes exactly', () {
      final before = surfaceOf([
        tileWith(origin, {
          (0, 0): [10, 20, 30, 255],
          (1, 0): [40, 50, 60, 128],
          (2, 0): [10, 20, 30, 7],
        }),
      ]);
      final pixels = [
        (origin, 0, 0, 255),
        (origin, 1, 0, 255),
        (origin, 2, 0, 255),
      ];

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.colour,
        walk: walk(pixels),
        value: Uint8List.fromList([1, 2, 3]),
      );
      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.colour,
        walk: walk(pixels),
        restore: forward.restore,
      );

      for (var x = 0; x < 3; x += 1) {
        expect(
          pixelAt(undone.surface, origin, x, 0),
          pixelAt(before, origin, x, 0),
          reason: 'pixel $x must come back byte for byte',
        );
      }
    });

    test('a few colours become a palette of index bytes', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [10, 10, 10, 255],
          (1, 0): [20, 20, 20, 255],
          (2, 0): [10, 10, 10, 255],
          (3, 0): [30, 30, 30, 255],
        }),
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([
          (origin, 0, 0, 255),
          (origin, 1, 0, 255),
          (origin, 2, 0, 255),
          (origin, 3, 0, 255),
        ]),
        value: Uint8List.fromList([0, 0, 255]),
      );

      final restore = result.restore! as PalettedCelPixelRestore;
      expect(restore.palette, [10, 10, 10, 20, 20, 20, 30, 30, 30]);
      expect(restore.indices, [0, 1, 0, 2]);
    });

    test('more than 256 colours falls back to raw channels', () {
      final pixels = <(int, int), List<int>>{};
      final walked = <_Pixel>[];
      for (var index = 0; index < 300; index += 1) {
        final x = index % 256;
        final y = index ~/ 256;
        pixels[(x, y)] = [index & 0xFF, (index >> 4) & 0xFF, index % 251, 255];
        walked.add((origin, x, y, 255));
      }
      final surface = surfaceOf([tileWith(origin, pixels)]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk(walked),
        value: Uint8List.fromList([0, 0, 0]),
      );

      final restore = result.restore! as RawCelPixelRestore;
      expect(restore.values.length, 300 * 3);

      final undone = overwriteCelPixels(
        surface: result.surface,
        channel: CelPixelChannel.colour,
        walk: walk(walked),
        restore: restore,
      );
      expect(pixelAt(undone.surface, origin, 5, 0), pixelAt(surface, origin, 5, 0));
      expect(
        pixelAt(undone.surface, origin, 43, 1),
        pixelAt(surface, origin, 43, 1),
      );
    });
  });

  group('soft mask', () {
    test('blends the colour and never the alpha', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [0, 0, 0, 200],
        }),
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, 0, 0, 128)]),
        value: Uint8List.fromList([255, 255, 255]),
      );

      final pixel = pixelAt(result.surface, origin, 0, 0);
      // Half coverage lands halfway between the two colours...
      expect(pixel[0], closeTo(128, 1));
      // ...and the shape is untouched. A stamp composited back through
      // src-over would have thickened this to ~228.
      expect(pixel[3], 200);
    });

    test('undo of a feathered pass is exact', () {
      final before = surfaceOf([
        tileWith(origin, {
          (0, 0): [10, 20, 30, 255],
          (1, 0): [10, 20, 30, 255],
          (2, 0): [10, 20, 30, 255],
        }),
      ]);
      final pixels = [
        (origin, 0, 0, 64),
        (origin, 1, 0, 128),
        (origin, 2, 0, 255),
      ];

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.colour,
        walk: walk(pixels),
        value: Uint8List.fromList([250, 240, 230]),
      );
      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.colour,
        walk: walk(pixels),
        restore: forward.restore,
      );

      // The recipe holds the ORIGINAL colour, so restoring it is a write —
      // not a second lerp, which would only ever converge toward the
      // original and never reach it.
      for (var x = 0; x < 3; x += 1) {
        expect(pixelAt(undone.surface, origin, x, 0), [10, 20, 30, 255]);
      }
    });
  });

  group('alpha channel (픽셀 비우기)', () {
    test('empties alpha, keeps the colour bytes, and undoes exactly', () {
      final before = surfaceOf([
        tileWith(origin, {
          (0, 0): [10, 20, 30, 255],
          (1, 0): [40, 50, 60, 128],
        }),
      ]);
      final pixels = [(origin, 0, 0, 255), (origin, 1, 0, 255)];

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.alpha,
        walk: walk(pixels),
        value: Uint8List.fromList([0]),
      );

      expect(pixelAt(forward.surface, origin, 0, 0), [10, 20, 30, 0]);
      expect(pixelAt(forward.surface, origin, 1, 0), [40, 50, 60, 0]);

      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.alpha,
        walk: walk(pixels),
        restore: forward.restore,
      );
      expect(pixelAt(undone.surface, origin, 0, 0), [10, 20, 30, 255]);
      expect(pixelAt(undone.surface, origin, 1, 0), [40, 50, 60, 128]);
    });

    test('records already-empty pixels so undo can tell them apart', () {
      final before = surfaceOf([
        tileWith(origin, {
          (0, 0): [0, 0, 0, 255],
          (1, 0): [0, 0, 0, 0],
          (2, 0): [0, 0, 0, 255],
        }),
      ]);
      final pixels = [
        (origin, 0, 0, 255),
        (origin, 1, 0, 255),
        (origin, 2, 0, 255),
      ];

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.alpha,
        walk: walk(pixels),
        value: Uint8List.fromList([0]),
      );
      // All three took part — skipping the empty one would shift every
      // later value by one on the way back.
      expect(forward.restore, isA<PalettedCelPixelRestore>());
      expect((forward.restore! as PalettedCelPixelRestore).indices.length, 3);

      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.alpha,
        walk: walk(pixels),
        restore: forward.restore,
      );
      expect(pixelAt(undone.surface, origin, 0, 0)[3], 255);
      expect(pixelAt(undone.surface, origin, 1, 0)[3], 0);
      expect(pixelAt(undone.surface, origin, 2, 0)[3], 255);
    });
  });

  group('tile economy', () {
    test('a tile the walk crosses without writing stays the same object', () {
      final untouched = tileWith(neighbour, {
        (0, 0): [9, 9, 9, 255],
      });
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [0, 0, 0, 255],
        }),
        untouched,
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([
          (origin, 0, 0, 255),
          // Crossed, but transparent there — nothing to recolour.
          (neighbour, 5, 5, 255),
        ]),
        value: Uint8List.fromList([1, 1, 1]),
      );

      expect(
        identical(result.surface.tileAt(neighbour), untouched),
        isTrue,
        reason: 'an untouched tile must stay shared with the old surface',
      );
      expect(identical(result.surface.tileAt(origin), surface.tileAt(origin)),
          isFalse);
    });

    test('an absent tile is never materialized', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [0, 0, 0, 255],
        }),
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, 0, 0, 255), (neighbour, 0, 0, 255)]),
        value: Uint8List.fromList([2, 2, 2]),
      );

      expect(result.surface.tileAt(neighbour), isNull);
    });
  });
}
