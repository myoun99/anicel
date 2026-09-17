import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/tile_pyramid.dart';

/// 🚨A LEVEL TILE IS ITS BLOCK HALVED (render round 4c, 2026-09-16): the
/// level-1 picture at (cx, cy) is the four tiles at (2cx.., 2cy..) each
/// halved into its quadrant — an exact box mean, made in the frame from
/// the pictures the cache holds — kept while those tiles stand and a
/// recent paint asked for it, remade when one of them is a new object or
/// was a stand-in, never made over a tile that has no picture yet, and
/// never made past the caller's ration.
void main() {
  const size = 4;
  const canvasSize = CanvasSize(width: 16, height: 16);
  const black = [0, 0, 0, 255];
  const white = [255, 255, 255, 255];

  /// A tile whose every pixel is [rgba].
  BitmapTile solid(List<int> rgba) {
    final pixels = Uint8List(size * size * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels.setRange(i, i + 4, rgba);
    }
    return BitmapTile(size: size, pixels: pixels);
  }

  /// A picture whose every pixel is [rgba], the size of a tile.
  ui.Image picture(List<int> rgba) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, size * 1.0, size * 1.0),
      ui.Paint()
        ..color = ui.Color.fromARGB(rgba[3], rgba[0], rgba[1], rgba[2]),
    );
    final recorded = recorder.endRecording();
    final image = recorded.toImageSync(size, size);
    recorded.dispose();
    return image;
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  List<int> at(Uint8List px, int x, int y) {
    final o = (y * size + x) * 4;
    return [px[o], px[o + 1], px[o + 2], px[o + 3]];
  }

  /// Gives [tile] its own picture, as a landed decode would.
  void adopt(BitmapTileImageCache cache, TileCoord coord, BitmapTile tile,
      List<int> rgba) {
    cache.adoptDecoded(
      (coord: coord, tile: tile),
      picture(rgba),
    );
  }

  /// What the surface pass answers for a coordinate of [surface] with
  /// [cache]'s pictures: the tile is the key of its own truth, a stand-in
  /// picture is the key of itself, and a tile without any picture is the
  /// key of a picture yet to come.
  LevelTileAsk askOf(
    BitmapSurface surface,
    BitmapTileImageCache cache, {
    bool Function()? mayMake,
  }) => (
    tileSize: surface.tileSize,
    scope: 'cel',
    keyAt: (TileCoord at) {
      final tile = surface.tileAt(at);
      if (tile == null) {
        return null;
      }
      return cache.imageFor(tile) != null
          ? tile
          : (cache.imageFor(tile) ?? tile);
    },
    pictureAt: (TileCoord at) {
      final tile = surface.tileAt(at);
      return tile == null ? null : cache.imageFor(tile);
    },
    mayMake: mayMake ?? () => true,
  );

  ui.Image? levelOne(
    TilePyramid pyramid,
    BitmapSurface surface,
    BitmapTileImageCache cache, {
    TileCoord? coord,
    bool Function()? mayMake,
  }) => pyramid.imageFor(
    askOf(surface, cache, mayMake: mayMake),
    level: 1,
    coord: coord ?? TileCoord(x: 0, y: 0),
  );

  testWidgets('the level-1 picture is the four tiles halved into their '
      'quadrants — and nothing where the block has no tile', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final pyramid = TilePyramid();
      final tiles = {
        TileCoord(x: 0, y: 0): solid(black),
        TileCoord(x: 1, y: 0): solid(white),
        TileCoord(x: 0, y: 1): solid(white),
        // (1, 1) has no tile: transparent in the level picture.
      };
      final surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: size,
        tiles: tiles,
      );
      for (final entry in tiles.entries) {
        adopt(
          cache,
          entry.key,
          entry.value,
          entry.key == TileCoord(x: 0, y: 0) ? black : white,
        );
      }
      final before = TilePyramid.liveBytes;
      final level = levelOne(pyramid, surface, cache);
      expect(level, isNotNull);
      expect(level!.width, size);
      expect(level.height, size);
      final px = await bytesOf(level);
      expect(at(px, 0, 0), black, reason: 'top-left quadrant: (0,0) halved');
      expect(at(px, 1, 1), black);
      expect(at(px, 2, 0), white, reason: 'top-right: (1,0)');
      expect(at(px, 0, 2), white, reason: 'bottom-left: (0,1)');
      expect(at(px, 3, 3), [0, 0, 0, 0], reason: 'no tile at (1,1)');
      expect(
        TilePyramid.liveBytes - before,
        size * size * 4,
        reason: 'one level tile counted for the census',
      );
    });
  });

  testWidgets('a level pixel is the exact mean of its 2×2 block', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final pyramid = TilePyramid();
      // Columns: x even black, x odd white — every 2×2 block is half ink.
      final pixels = Uint8List(size * size * 4);
      for (var y = 0; y < size; y += 1) {
        for (var x = 0; x < size; x += 1) {
          pixels.setRange((y * size + x) * 4, (y * size + x) * 4 + 4,
              x.isEven ? black : white);
        }
      }
      final tile = BitmapTile(size: size, pixels: pixels);
      final coord = TileCoord(x: 0, y: 0);
      final surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: size,
        tiles: {coord: tile},
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (var x = 0; x < size; x += 1) {
        canvas.drawRect(
          ui.Rect.fromLTWH(x * 1.0, 0, 1, size * 1.0),
          ui.Paint()
            ..color = x.isEven
                ? const ui.Color(0xFF000000)
                : const ui.Color(0xFFFFFFFF),
        );
      }
      final recorded = recorder.endRecording();
      cache.adoptDecoded(
        (coord: coord, tile: tile),
        recorded.toImageSync(size, size),
      );
      recorded.dispose();
      final level = levelOne(pyramid, surface, cache);
      final px = await bytesOf(level!);
      for (var y = 0; y < size ~/ 2; y += 1) {
        for (var x = 0; x < size ~/ 2; x += 1) {
          expect(
            at(px, x, y)[0],
            inInclusiveRange(126, 129),
            reason: '($x,$y): half black, half white — the box mean, '
                'not one texel of the two (0 or 255)',
          );
        }
      }
    });
  });

  testWidgets('kept while its tiles stand, remade when one is a new object, '
      'and not made over a tile without a picture', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final pyramid = TilePyramid();
      final first = solid(black);
      final coord = TileCoord(x: 0, y: 0);
      var surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: size,
        tiles: {coord: first},
      );
      expect(
        levelOne(pyramid, surface, cache),
        isNull,
        reason: 'the tile has no picture yet: the block waits',
      );
      adopt(cache, coord, first, black);
      final made = levelOne(pyramid, surface, cache);
      expect(made, isNotNull);
      expect(
        identical(levelOne(pyramid, surface, cache), made),
        isTrue,
        reason: 'the same tiles: the same picture, not a remake',
      );

      // A commit: a new tile object at the coordinate.
      final second = solid(black);
      surface = surface.copyWith(tiles: {coord: second});
      expect(
        levelOne(pyramid, surface, cache),
        isNull,
        reason: 'the new tile has no picture yet',
      );
      adopt(cache, coord, second, black);
      final remade = levelOne(pyramid, surface, cache);
      expect(remade, isNotNull);
      expect(
        identical(remade, made),
        isFalse,
        reason: 'remade over the new tile',
      );
    });
  });

  testWidgets('the ration is the caller\'s: refused, nothing is made — and '
      'what an earlier paint made is kept for the next', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final pyramid = TilePyramid();
      final tiles = {
        for (var y = 0; y < 4; y += 1)
          for (var x = 0; x < 4; x += 1) TileCoord(x: x, y: y): solid(black),
      };
      final surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: size,
        tiles: tiles,
      );
      for (final entry in tiles.entries) {
        adopt(cache, entry.key, entry.value, black);
      }
      ui.Image? levelTwo(int ration) {
        var left = ration;
        return pyramid.imageFor(
          askOf(
            surface,
            cache,
            mayMake: () {
              if (left <= 0) {
                return false;
              }
              left -= 1;
              return true;
            },
          ),
          level: 2,
          coord: TileCoord(x: 0, y: 0),
        );
      }

      final before = TilePyramid.liveBytes;
      expect(levelTwo(0), isNull, reason: 'no ration, nothing made');
      expect(TilePyramid.liveBytes, before);
      // Two of the four level-1 children fit; the level-2 tile does not.
      expect(levelTwo(2), isNull);
      expect(TilePyramid.liveBytes - before, 2 * size * size * 4);
      // The next paint's ration finishes it: two children + the parent.
      expect(levelTwo(3), isNotNull);
      expect(TilePyramid.liveBytes - before, 5 * size * size * 4);
    });
  });

  testWidgets('a level tile no recent paint asked for is let go', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final pyramid = TilePyramid();
      final tile = solid(black);
      final coord = TileCoord(x: 0, y: 0);
      final surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: size,
        tiles: {coord: tile},
      );
      adopt(cache, coord, tile, black);
      final before = TilePyramid.liveBytes;
      pyramid.paintBegan('cel');
      final made = levelOne(pyramid, surface, cache);
      pyramid.paintEnded('cel');
      expect(made, isNotNull);
      for (var i = 0; i < TilePyramid.recentPaints; i += 1) {
        pyramid.paintBegan('cel');
        pyramid.paintEnded('cel');
      }
      expect(
        TilePyramid.liveBytes - before,
        size * size * 4,
        reason: 'within the recent paints: kept',
      );
      pyramid.paintBegan('cel');
      pyramid.paintEnded('cel');
      expect(
        TilePyramid.liveBytes,
        before,
        reason: 'one paint past the allowance: let go',
      );
      pyramid.paintBegan('cel');
      expect(
        identical(levelOne(pyramid, surface, cache), made),
        isFalse,
        reason: 'asked again: made anew',
      );
      pyramid.paintEnded('cel');
    });
  });
}
