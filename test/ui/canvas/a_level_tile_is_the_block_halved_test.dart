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
/// halved into its quadrant — an exact box mean, made in the ask from the
/// tiles' own pictures (each made in the same ask if it has none) — kept
/// while those tiles stand and a recent paint asked for it, remade when
/// one of them is a new object, and made WHOLE by the one ask that needs
/// it, however many level tiles that takes (🪦the ration and the "tile
/// without a picture waits" rule both went on 2026-09-17: a block either
/// of them stopped stayed nearest-sampled on screen, see [TilePyramid]).
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
      tile,
      picture(rgba),
    );
  }

  /// What the surface pass answers for a coordinate of [surface] with
  /// [cache]'s pictures, the way `_CoordinatePicture` does: the tile is
  /// the key, and its picture is the one it has or the one made now.
  LevelTileAsk askOf(BitmapSurface surface, BitmapTileImageCache cache) => (
    tileSize: surface.tileSize,
    scope: 'cel',
    keyAt: (TileCoord at) => surface.tileAt(at),
    pictureAt: (TileCoord at) {
      final tile = surface.tileAt(at);
      return tile == null ? null : cache.pictureFor(tile);
    },
  );

  ui.Image? levelOne(
    TilePyramid pyramid,
    BitmapSurface surface,
    BitmapTileImageCache cache, {
    TileCoord? coord,
  }) => pyramid.imageFor(
    askOf(surface, cache),
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
        tile,
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

  testWidgets('made over a tile that has no picture yet — the ask makes it '
      '— kept while its tiles stand, remade when one is a new object', (
    tester,
  ) async {
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
      expect(cache.imageFor(first), isNull, reason: 'fixture: no picture yet');
      final made = levelOne(pyramid, surface, cache);
      expect(
        made,
        isNotNull,
        reason: 'the block does not wait for a picture: the ask makes the '
            'tile\'s picture and halves it',
      );
      expect(at(await bytesOf(made!), 0, 0), black);
      expect(cache.imageFor(first), isNotNull);
      expect(
        identical(levelOne(pyramid, surface, cache), made),
        isTrue,
        reason: 'the same tiles: the same picture, not a remake',
      );

      // A commit: a new tile object at the coordinate.
      final second = solid(white);
      surface = surface.copyWith(tiles: {coord: second});
      final remade = levelOne(pyramid, surface, cache);
      expect(remade, isNotNull);
      expect(
        identical(remade, made),
        isFalse,
        reason: 'remade over the new tile',
      );
      expect(at(await bytesOf(remade!), 0, 0), white);
    });
  });

  testWidgets('one ask makes a level-2 tile WHOLE — its four level-1 '
      'children and itself — with no ration to stop it half way', (
    tester,
  ) async {
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
      final before = TilePyramid.liveBytes;
      final levelTwo = pyramid.imageFor(
        askOf(surface, cache),
        level: 2,
        coord: TileCoord(x: 0, y: 0),
      );
      expect(levelTwo, isNotNull);
      expect(
        TilePyramid.liveBytes - before,
        5 * size * size * 4,
        reason: 'four level-1 children and the level-2 tile, in one ask',
      );
      final px = await bytesOf(levelTwo!);
      for (var y = 0; y < size; y += 1) {
        for (var x = 0; x < size; x += 1) {
          expect(at(px, x, y), black, reason: '($x,$y): every tile is ink');
        }
      }
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
