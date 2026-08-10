import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/provisional_tile_pictures.dart';

/// Composing a just-committed tile's picture out of pictures already on
/// the GPU.
///
/// Almost everything here is about what it REFUSES to do. Publishing a
/// composed tile is publishing a picture, and a picture with a piece
/// missing is worse than the coordinate's current answer — the program's
/// invariant allows trading fidelity and forbids trading coverage. So
/// every operand this cannot draw has to turn into "leave it alone", and
/// those are the tests that would let a silent hole through if they
/// stopped holding.
void main() {
  const tileSize = 2;

  BitmapTile tile(TileCoord coord, {RgbaColor? at00}) {
    var made = BitmapTile.blank(coord: coord, size: tileSize);
    if (at00 != null) {
      made = writeRgbaColorToBitmapTile(tile: made, x: 0, y: 0, color: at00);
    }
    return made;
  }

  BitmapSurface surfaceOf(List<BitmapTile> tiles, {int width = 4}) =>
      BitmapSurface(
        canvasSize: CanvasSize(width: width, height: tileSize),
        tileSize: tileSize,
        tiles: {for (final t in tiles) t.coord: t},
      );

  ui.Image solid(int size, Color color) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = color,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
  final coord0 = TileCoord(x: 0, y: 0);
  final coord1 = TileCoord(x: 1, y: 0);

  /// Ink that covers everything it is asked about, so a test about the
  /// PRE operand is not also a test about the ink.
  ProvisionalInkPainter greenEverywhere() =>
      (canvas, region) {
        canvas.drawRect(region, Paint()..color = const Color(0xFF00FF00));
        return true;
      };

  test('a coordinate whose pre-commit pixels have no picture is left '
      'alone', () {
    final cache = BitmapTileImageCache();
    // Both coordinates HAD artwork. Only the first one's picture is on
    // the GPU.
    final preWithPicture = tile(coord0, at00: red);
    final preWithout = tile(coord1, at00: red);
    cache.adoptDecoded(preWithPicture, solid(tileSize, const Color(0xFF0000FF)));

    final post = surfaceOf([tile(coord0), tile(coord1)]);
    final result = seedProvisionalTilePictures(
      preSurface: surfaceOf([preWithPicture, preWithout]),
      postSurface: post,
      coords: [coord0, coord1],
      ink: greenEverywhere(),
      cache: cache,
    );

    expect(result.seeded, 1);
    expect(result.skipped, 1);
    expect(cache.hasProvisional(post.tileAt(coord0)!), isTrue);
    expect(
      cache.hasProvisional(post.tileAt(coord1)!),
      isFalse,
      reason:
          'composing here would publish a tile with the artwork that was '
          'under the ink missing — a hole wearing a picture',
    );
  });

  test('an empty pre-commit coordinate needs no picture to compose on', () {
    final cache = BitmapTileImageCache();
    // Blank tile, no image: there is nothing to lose, so the ink alone is
    // the whole truth. This is the lift case — the erase took the
    // coordinate whole.
    final post = surfaceOf([tile(coord0)]);
    final result = seedProvisionalTilePictures(
      preSurface: surfaceOf([tile(coord0)]),
      postSurface: post,
      coords: [coord0],
      ink: greenEverywhere(),
      cache: cache,
    );

    expect(result.seeded, 1);
    expect(cache.hasProvisional(post.tileAt(coord0)!), isTrue);
  });

  test('a tile that already has its own picture is not given a second '
      'one', () {
    final cache = BitmapTileImageCache();
    final post = surfaceOf([tile(coord0, at00: red)]);
    cache.adoptDecoded(post.tileAt(coord0)!, solid(tileSize, const Color(0xFF0000FF)));

    final result = seedProvisionalTilePictures(
      preSurface: surfaceOf([tile(coord0)]),
      postSurface: post,
      coords: [coord0],
      ink: greenEverywhere(),
      cache: cache,
    );

    expect(result.seeded, 0);
    expect(cache.hasProvisional(post.tileAt(coord0)!), isFalse);
  });

  test('ink that cannot draw all of itself composes nothing', () {
    final cache = BitmapTileImageCache();
    // A float whose tile HAS pixels but no decoded picture: the surface
    // ink source has to say so rather than draw around it.
    final floatTile = tile(coord0, at00: red);
    final float = surfaceOf([floatTile]);

    final post = surfaceOf([tile(coord0)]);
    final result = seedProvisionalTilePictures(
      preSurface: surfaceOf([tile(coord0)]),
      postSurface: post,
      coords: [coord0],
      ink: inkFromSurface(float, Offset.zero, cache: cache),
      cache: cache,
    );

    expect(result.seeded, 0);
    expect(cache.hasProvisional(post.tileAt(coord0)!), isFalse);

    // Same fixture, same call, with the float's picture on the GPU: now
    // it composes. Without this half the test above passes for a
    // `seedProvisionalTilePictures` that never seeds anything.
    cache.adoptDecoded(floatTile, solid(tileSize, const Color(0xFF00FF00)));
    final second = seedProvisionalTilePictures(
      preSurface: surfaceOf([tile(coord0)]),
      postSurface: post,
      coords: [coord0],
      ink: inkFromSurface(float, Offset.zero, cache: cache),
      cache: cache,
    );
    expect(second.seeded, 1);
  });

  testWidgets('the composed picture IS the pre picture with the ink over '
      'it', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      // Opaque blue underneath, half-transparent green on top: the result
      // has to be the blend, not either operand.
      final pre = tile(coord0, at00: red);
      cache.adoptDecoded(pre, solid(tileSize, const Color(0xFF0000FF)));
      final post = surfaceOf([tile(coord0)]);

      seedProvisionalTilePictures(
        preSurface: surfaceOf([pre]),
        postSurface: post,
        coords: [coord0],
        ink: (canvas, region) {
          canvas.drawRect(region, Paint()..color = const Color(0x8000FF00));
          return true;
        },
        cache: cache,
      );

      final composed = cache.displayImageFor(post.tileAt(coord0)!);
      expect(composed, isNotNull);
      final data = await composed!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final bytes = data!.buffer.asUint8List();
      // srcOver of 50% green over opaque blue: red gone, both others
      // present, fully opaque.
      expect(bytes[0], 0, reason: 'no red in either operand');
      expect(bytes[1], greaterThan(100), reason: 'the green went on');
      expect(bytes[2], greaterThan(100), reason: 'the blue is still under it');
      expect(bytes[3], 255);
    });
  });

  testWidgets('ink past the pasteboard wall is not composed in', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      // The commit clips at the pasteboard wall, so the composition has
      // to. A 3-wide canvas walls off at x = 9 (the pasteboard runs to
      // three canvas widths), and a 2 px tile at column 4 STRADDLES it:
      // x = 8 is on, x = 9 is off. Without the clip the composed tile
      // shows ink at x = 9 for a frame and then loses it when the real
      // decode lands without it — a picture that promises what the commit
      // did not deliver.
      final edge = TileCoord(x: 4, y: 0);
      final post = surfaceOf([tile(edge)], width: 3);
      final seeded = seedProvisionalTilePictures(
        preSurface: surfaceOf([tile(edge)], width: 3),
        postSurface: post,
        coords: [edge],
        ink: (canvas, region) {
          canvas.drawRect(
            const Rect.fromLTWH(-100, -100, 400, 400),
            Paint()..color = const Color(0xFF00FF00),
          );
          return true;
        },
        cache: cache,
      );
      expect(seeded.seeded, 1);

      final composed = cache.displayImageFor(post.tileAt(edge)!)!;
      final data = await composed.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      expect(bytes[3], 255, reason: 'canvas x=8 is inside the wall');
      expect(
        bytes[7],
        0,
        reason: 'canvas x=9 is past the wall, where the commit writes '
            'nothing',
      );
    });
  });
}
