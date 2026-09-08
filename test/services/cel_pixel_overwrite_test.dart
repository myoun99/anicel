import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';

void main() {
  const canvas = CanvasSize(width: 512, height: 512);
  final origin = TileCoord(x: 0, y: 0);
  final neighbour = TileCoord(x: 1, y: 0);

  /// A tile carrying [pixels] at the given tile-local coordinates,
  /// everything else fully transparent.
  BitmapTile tileWith(TileCoord coord, Map<(int, int), List<int>> pixels) {
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

  /// Coverage over the named tile-local pixels; everything else 0.
  Uint8List maskOver(Map<(int, int), int> coverage) {
    final mask = Uint8List(256 * 256);
    for (final entry in coverage.entries) {
      mask[(entry.key.$2 * 256) + entry.key.$1] = entry.value;
    }
    return mask;
  }

  /// Full coverage of the named pixels.
  Uint8List maskOverAll(Iterable<(int, int)> pixels) =>
      maskOver({for (final pixel in pixels) pixel: 255});

  CelPixelWalk walk(List<(TileCoord, Uint8List?)> tiles) => (visit) {
    for (final tile in tiles) {
      visit(tile.$1, tile.$2);
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
        walk: walk([
          (origin, maskOverAll([(0, 0), (1, 0)])),
        ]),
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
        walk: walk([
          (origin, maskOverAll([(0, 0)])),
        ]),
        value: Uint8List.fromList([255, 0, 0]),
      );

      // Nothing participated, so nothing was rebuilt at all.
      expect(result.restore, isNull);
      expect(identical(result.surface, surface), isTrue);
    });

    test('a whole-tile pass with no mask touches only the ink', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (7, 3): [17, 17, 17, 255],
          (8, 3): [17, 17, 17, 128],
        }),
      ]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        // null mask = 범위는 전체.
        walk: walk([(origin, null)]),
        value: Uint8List.fromList([200, 30, 30]),
      );

      expect(pixelAt(result.surface, origin, 7, 3), [200, 30, 30, 255]);
      expect(pixelAt(result.surface, origin, 8, 3), [200, 30, 30, 128]);
      // The other 65534 transparent pixels stayed out of the recipe.
      final restore = result.restore! as UniformCelPixelRestore;
      expect(restore.value, [17, 17, 17]);
      expect(restore.estimatedRetainedBytes, 3);
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
        walk: walk([
          (origin, maskOverAll([for (var x = 0; x < 40; x += 1) (x, 0)])),
        ]),
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
      final steps = walk([
        (origin, maskOverAll([(0, 0), (1, 0), (2, 0)])),
      ]);

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.colour,
        walk: steps,
        value: Uint8List.fromList([1, 2, 3]),
      );
      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.colour,
        walk: steps,
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
      // ⚠️SIX pixels, not four, and the number is load-bearing: a palette
      // has to carry its table, so it only becomes the smallest answer once
      // there are more pixels than the table costs (9 bytes of table + n
      // index bytes against 3n raw bytes ⇒ n ≥ 5). At four pixels the raw
      // channels are literally one byte smaller, and the recipe shape is
      // whichever is smallest — see `_RestoreBuilder.build`.
      final art = <(int, int), List<int>>{
        (0, 0): [10, 10, 10, 255],
        (1, 0): [20, 20, 20, 255],
        (2, 0): [10, 10, 10, 255],
        (3, 0): [30, 30, 30, 255],
        (4, 0): [20, 20, 20, 255],
        (5, 0): [30, 30, 30, 255],
      };
      final surface = surfaceOf([tileWith(origin, art)]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, maskOverAll(art.keys))]),
        value: Uint8List.fromList([0, 0, 255]),
      );

      final restore = result.restore! as PalettedCelPixelRestore;
      expect(restore.palette, [10, 10, 10, 20, 20, 20, 30, 30, 30]);
      expect(restore.indices, [0, 1, 0, 2, 1, 2]);
      expect(restore.estimatedRetainedBytes, 15);
    });

    test('more than 256 colours falls back to raw channels', () {
      final pixels = <(int, int), List<int>>{};
      final covered = <(int, int)>[];
      for (var index = 0; index < 300; index += 1) {
        final x = index % 256;
        final y = index ~/ 256;
        pixels[(x, y)] = [index & 0xFF, (index >> 4) & 0xFF, index % 251, 255];
        covered.add((x, y));
      }
      final surface = surfaceOf([tileWith(origin, pixels)]);
      final steps = walk([(origin, maskOverAll(covered))]);

      final result = overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.colour,
        walk: steps,
        value: Uint8List.fromList([0, 0, 0]),
      );

      final restore = result.restore! as RawCelPixelRestore;
      expect(restore.values.length, 300 * 3);

      final undone = overwriteCelPixels(
        surface: result.surface,
        channel: CelPixelChannel.colour,
        walk: steps,
        restore: restore,
      );
      expect(
        pixelAt(undone.surface, origin, 5, 0),
        pixelAt(surface, origin, 5, 0),
      );
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
        walk: walk([
          (origin, maskOver({(0, 0): 128})),
        ]),
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
      final steps = walk([
        (origin, maskOver({(0, 0): 64, (1, 0): 128, (2, 0): 255})),
      ]);

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.colour,
        walk: steps,
        value: Uint8List.fromList([250, 240, 230]),
      );
      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.colour,
        walk: steps,
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
      final steps = walk([
        (origin, maskOverAll([(0, 0), (1, 0)])),
      ]);

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.alpha,
        walk: steps,
        value: Uint8List.fromList([0]),
      );

      expect(pixelAt(forward.surface, origin, 0, 0), [10, 20, 30, 0]);
      expect(pixelAt(forward.surface, origin, 1, 0), [40, 50, 60, 0]);

      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.alpha,
        walk: steps,
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
      final steps = walk([
        (origin, maskOverAll([(0, 0), (1, 0), (2, 0)])),
      ]);

      final forward = overwriteCelPixels(
        surface: before,
        channel: CelPixelChannel.alpha,
        walk: steps,
        value: Uint8List.fromList([0]),
      );
      // All three took part — skipping the empty one would shift every
      // later value by one on the way back.
      //
      // ⚠️Asked of the RECIPE, not of its shape: which shape is smallest
      // for three bytes is an accounting detail (raw wins here), while
      // "position 1 remembers the pixel that was already empty" is the law.
      final recorded = <int>[];
      for (var index = 0; index < 3; index += 1) {
        final into = Uint8List(1);
        forward.restore!.readInto(into, index);
        recorded.add(into.first);
      }
      expect(recorded, [255, 0, 255]);

      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.alpha,
        walk: steps,
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
          (origin, maskOverAll([(0, 0)])),
          // Crossed, but transparent there — nothing to recolour.
          (neighbour, maskOverAll([(5, 5)])),
        ]),
        value: Uint8List.fromList([1, 1, 1]),
      );

      expect(
        identical(result.surface.tileAt(neighbour), untouched),
        isTrue,
        reason: 'an untouched tile must stay shared with the old surface',
      );
      expect(
        identical(result.surface.tileAt(origin), surface.tileAt(origin)),
        isFalse,
      );
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
        walk: walk([(origin, null), (neighbour, null)]),
        value: Uint8List.fromList([2, 2, 2]),
      );

      expect(result.surface.tileAt(neighbour), isNull);
    });
  });

  /// 🚨THE TIER THE LADDER COULD NOT REACH. A palette index is one byte PER
  /// PIXEL however few colours there are, and beyond 256 colours the recipe
  /// used to be the whole channel per pixel — so a pass over an ordinary
  /// shaded drawing paid megabytes to say the same value over and over.
  ///
  /// Every case here is paired with the mutation that must turn it red.
  group('a repeating pre-image is said once per run', () {
    /// [runs] stretches of [runLength] pixels each, laid along row 0 and
    /// wrapping, every stretch a different colour.
    ({BitmapSurface surface, List<(int, int)> covered}) banded({
      required int runs,
      required int runLength,
      required int Function(int band) colour,
    }) {
      final pixels = <(int, int), List<int>>{};
      final covered = <(int, int)>[];
      for (var index = 0; index < runs * runLength; index += 1) {
        final at = (index % 256, index ~/ 256);
        final value = colour(index ~/ runLength);
        pixels[at] = [value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, 255];
        covered.add(at);
      }
      return (surface: surfaceOf([tileWith(origin, pixels)]), covered: covered);
    }

    test('long stretches beat one index per pixel — and by a lot', () {
      final art = banded(runs: 8, runLength: 200, colour: (band) => band * 4919);

      final result = overwriteCelPixels(
        surface: art.surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, maskOverAll(art.covered))]),
        value: Uint8List.fromList([0, 0, 255]),
      );

      final restore = result.restore! as RunLengthCelPixelRestore;
      expect(restore.lengths, List<int>.filled(8, 200));
      // ⛔The number is the point, not the type: 8 runs × (3 value + 4
      // length) against 1,600 index bytes plus a palette.
      expect(restore.estimatedRetainedBytes, 56);
      expect(art.covered.length, 1600);
    });

    test('🚨and it rescues the case that used to cost four bytes a pixel — '
        'more than 256 colours, in stretches', () {
      // The palette overflows at 256, so the old ladder had no answer left
      // but the channels themselves.
      final art = banded(runs: 300, runLength: 20, colour: (band) => band * 7919);

      final result = overwriteCelPixels(
        surface: art.surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, maskOverAll(art.covered))]),
        value: Uint8List.fromList([0, 0, 255]),
      );

      final restore = result.restore! as RunLengthCelPixelRestore;
      expect(restore.estimatedRetainedBytes, 300 * 7);
      expect(
        restore.estimatedRetainedBytes,
        lessThan(art.covered.length * 3),
        reason: 'raw would have been three bytes for every one of 6,000 pixels',
      );
    });

    test('undo through a run recipe restores the original bytes exactly', () {
      final art = banded(runs: 5, runLength: 50, colour: (band) => band * 4919);
      final before = [
        for (final at in art.covered)
          pixelAt(art.surface, origin, at.$1, at.$2),
      ];

      final forward = overwriteCelPixels(
        surface: art.surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, maskOverAll(art.covered))]),
        value: Uint8List.fromList([0, 0, 255]),
      );
      expect(forward.restore, isA<RunLengthCelPixelRestore>());

      final undone = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, maskOverAll(art.covered))]),
        restore: forward.restore,
      );

      for (var i = 0; i < art.covered.length; i += 1) {
        final at = art.covered[i];
        expect(
          pixelAt(undone.surface, origin, at.$1, at.$2),
          before[i],
          reason: 'pixel $at came back through run ${i ~/ 50}',
        );
      }

      // 🚨AND AGAIN, on the same recipe object. A run recipe reads through a
      // CURSOR, so a second pass starts at index 0 with the cursor parked at
      // the end of the last one — it has to notice and walk back. Undo, redo
      // and undo again is an ordinary thing to do.
      final second = overwriteCelPixels(
        surface: forward.surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, maskOverAll(art.covered))]),
        restore: forward.restore,
      );
      for (var i = 0; i < art.covered.length; i += 1) {
        final at = art.covered[i];
        expect(pixelAt(second.surface, origin, at.$1, at.$2), before[i]);
      }
    });

    test('⛔interleaved values keep the palette — a run that is one pixel '
        'long costs more than the value it stands for', () {
      final art = banded(runs: 300, runLength: 1, colour: (band) => band % 3);

      final result = overwriteCelPixels(
        surface: art.surface,
        channel: CelPixelChannel.colour,
        walk: walk([(origin, maskOverAll(art.covered))]),
        value: Uint8List.fromList([0, 0, 255]),
      );

      expect(result.restore, isA<PalettedCelPixelRestore>());
    });
  });
}
