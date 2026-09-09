import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';

/// R26 #13 follow-up: the tight ink bounding box — the whole-picture
/// transform box frames exactly the picture.
void main() {
  const tileSize = 4;

  BitmapTile tileWithInk(
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
    return BitmapTile(coord: coord, size: tileSize, pixels: pixels);
  }

  test('spans ink across tiles, in canvas coordinates', () {
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 12, height: 12),
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): tileWithInk(TileCoord(x: 0, y: 0), [
          (x: 2, y: 1),
        ]),
        TileCoord(x: 2, y: 1): tileWithInk(TileCoord(x: 2, y: 1), [
          (x: 3, y: 2),
        ]),
      },
    );

    expect(bitmapSurfaceContentBounds(surface), (
      left: 2,
      top: 1,
      rightExclusive: 12,
      bottomExclusive: 7,
    ));
  });

  test('🚨the box reaches the FARTHEST ink in a tile, not the first — a '
      'run inside one tile has a left and a right', () {
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 12, height: 12),
      tileSize: tileSize,
      tiles: {
        // One tile, ink from (1,0) to (3,2): the box has to be three
        // wide and three tall. Every earlier fixture inked a SINGLE
        // pixel per tile, so left == right and top == bottom, and a
        // fold that kept the near edge for both read as correct.
        TileCoord(x: 1, y: 1): tileWithInk(TileCoord(x: 1, y: 1), [
          (x: 1, y: 0),
          (x: 3, y: 2),
        ]),
      },
    );

    expect(bitmapSurfaceContentBounds(surface), (
      left: 5,
      top: 4,
      rightExclusive: 8,
      bottomExclusive: 7,
    ));
  });

  test('alpha-zero pixels are NOT ink (colored-but-transparent bytes '
      'never widen the box); a blank surface answers null', () {
    final ghostInk = BitmapSurface(
      canvasSize: const CanvasSize(width: 8, height: 8),
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): tileWithInk(TileCoord(x: 0, y: 0), [
          (x: 0, y: 0),
        ], alpha: 0),
        TileCoord(x: 1, y: 1): tileWithInk(TileCoord(x: 1, y: 1), [
          (x: 1, y: 1),
        ]),
      },
    );
    expect(bitmapSurfaceContentBounds(ghostInk), (
      left: 5,
      top: 5,
      rightExclusive: 6,
      bottomExclusive: 6,
    ));

    expect(
      bitmapSurfaceContentBounds(
        BitmapSurface(
          canvasSize: const CanvasSize(width: 8, height: 8),
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
    /// ⛔BOTH ROUTES, and the mutation is why: with the engine loaded
    /// the batched C scan is what remembers, and a mutant that made
    /// the Dart getter forget survived the whole file (2026-09-09).
    /// The two paths memoize in different places and each needs its
    /// own witness.
    for (final dartOnly in [false, true]) {
      test(
        'a scan leaves every inked tile knowing its own box'
        ' (dart fallback: $dartOnly)',
        () {
          QaNativeEngine.debugForceDartFallback = dartOnly;
          addTearDown(() => QaNativeEngine.debugForceDartFallback = false);
          final untouched = tileWithInk(TileCoord(x: 0, y: 0), [(x: 2, y: 1)]);
          expect(
            untouched.inkBoundsKnown,
            isFalse,
            reason: 'a fresh tile has scanned nothing yet',
          );

          bitmapSurfaceContentBounds(
            BitmapSurface(
              canvasSize: const CanvasSize(width: 12, height: 12),
              tileSize: tileSize,
              tiles: {untouched.coord: untouched},
            ),
          );

          expect(untouched.inkBoundsKnown, isTrue);
          expect(untouched.inkBounds, (
            left: 2,
            top: 1,
            rightExclusive: 3,
            bottomExclusive: 2,
          ));
        },
      );
    }

    test('the tiles a commit carried over owe nothing on the next scan', () {
      final untouched = tileWithInk(TileCoord(x: 0, y: 0), [(x: 2, y: 1)]);
      final before = BitmapSurface(
        canvasSize: const CanvasSize(width: 12, height: 12),
        tileSize: tileSize,
        tiles: {untouched.coord: untouched},
      );
      bitmapSurfaceContentBounds(before);

      // What a commit does: one tile replaced, every other tile carried
      // over by reference.
      final committed = tileWithInk(TileCoord(x: 2, y: 1), [(x: 3, y: 2)]);
      final after = before.putTiles([committed]);
      expect(identical(after.tileAt(untouched.coord), untouched), isTrue);
      expect(
        committed.inkBoundsKnown,
        isFalse,
        reason: 'the tile the stroke made is the one that still owes a scan',
      );

      expect(bitmapSurfaceContentBounds(after), (
        left: 2,
        top: 1,
        rightExclusive: 12,
        bottomExclusive: 7,
      ));
      // And the carried-over tile answered from its memo throughout.
      expect(untouched.inkBoundsKnown, isTrue);
      expect(committed.inkBoundsKnown, isTrue);
    });

    test('an ink-free tile owes nothing either', () {
      final blank = BitmapTile.blank(
        coord: TileCoord(x: 0, y: 0),
        size: tileSize,
      );
      expect(blank.inkBounds, isNull);
      expect(blank.inkBoundsKnown, isTrue);
    });
  });
}
