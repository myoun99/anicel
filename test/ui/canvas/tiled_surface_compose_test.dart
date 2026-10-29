import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/raster_picture.dart';
import 'package:anicel/src/ui/canvas/tile_blocks.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

import '../../helpers/awaited_uploads.dart';
import '../../helpers/one_piece.dart';
import '../../helpers/premultiplied_canvas_bytes.dart';

/// The per-tile GPU compose must be byte-identical to the tiles' own bytes
/// where they stand ([premultipliedCanvasBytes]) — with and without cache
/// reuse — and turn the post-stroke rebuild into cache-hit draws.
void main() {
  BitmapSurface patternedSurface(CanvasSize canvasSize) {
    var surface = BitmapSurface(canvasSize: canvasSize, tileSize: 256);
    final columns = (canvasSize.width + 255) ~/ 256;
    final rows = (canvasSize.height + 255) ~/ 256;
    for (var tileY = 0; tileY < rows; tileY += 1) {
      for (var tileX = 0; tileX < columns; tileX += 1) {
        final pixels = Uint8List(256 * 256 * 4);
        for (var index = 0; index < pixels.length; index += 4) {
          final pixel = index >> 2;
          pixels[index] = (pixel * 7 + tileX) & 0xFF;
          pixels[index + 1] = (pixel * 13 + tileY) & 0xFF;
          pixels[index + 2] = (pixel * 29) & 0xFF;
          pixels[index + 3] = (pixel * 5) % 256; // 0 / mid / 255 regimes
        }
        surface = surface.putTiles([
          (
            coord: TileCoord(x: tileX, y: tileY),
            tile: BitmapTile(size: 256, pixels: pixels),
          ),
        ]);
      }
    }
    return surface;
  }

  /// A cel of [count] small tiles in a row, each with ink and none with a
  /// picture — each in a block of its own ([tileBlockEdge]), so each is a
  /// picture of its own.
  BitmapSurface rowOfTiles(int count) {
    const size = 8;
    const apart = tileBlockEdge ~/ size;
    var surface = BitmapSurface(
      canvasSize: CanvasSize(
        width: size * (apart * (count - 1) + 1),
        height: size,
      ),
      tileSize: size,
    );
    for (var x = 0; x < count; x += 1) {
      surface = surface.putTiles([
        (
          coord: TileCoord(x: x * apart, y: 0),
          tile: BitmapTile(
            size: size,
            pixels: Uint8List(size * size * 4)
              ..fillRange(0, size * size * 4, 0xFF),
          ),
        ),
      ]);
    }
    return surface;
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> seedCache(
    BitmapTileImageCache cache,
    BitmapSurface surface,
  ) async {
    for (final entry in surface.tiles.entries) {
      cache.pictureFor(entry.value);
    }
  }

  testWidgets('tile compose is byte-identical to the tiles\' own bytes, with '
      'and without cache reuse', (tester) async {
    await tester.runAsync(() async {
      // Partial edge tiles on both axes.
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );

      final reference = premultipliedCanvasBytes(surface);

      final cold = await bytesOf((await composeTiledSurfaceImage(surface))!);
      expect(cold, reference, reason: 'transient pictures, made in turn');

      final cache = BitmapTileImageCache();
      await seedCache(cache, surface);
      final warm = await bytesOf(
        (await composeTiledSurfaceImage(surface, reuse: cache))!,
      );
      expect(warm, reference, reason: 'cache-reuse path');
    });
  });

  testWidgets('the compose made NOW is the same picture: cold tiles pictured '
      'inside the call, through the one door — and kept for the next one', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );
      final reference = premultipliedCanvasBytes(surface);

      final cache = BitmapTileImageCache();
      expect(
        surface.tiles.values.every((tile) => cache.heldFor(tile) == null),
        isTrue,
        reason: 'fixture: nothing has pictured these tiles',
      );
      final now = composeTiledSurfaceImageNow(surface, reuse: cache);
      expect(
        surface.tiles.values.every((tile) => cache.heldFor(tile) != null),
        isTrue,
        reason: 'the pictures it made are the cache\'s: the next compose of '
            'this cel — the next edit — pays for the tiles that changed',
      );
      expect(await bytesOf(now), reference);
    });
  });

  /// ↩️A halved compose could be taken as a step of a chain, not waited for,
  /// and a positioned one made now beside its snapshot, until no row image
  /// was made (one-picture-per-frame ②-5b-1).
  testWidgets('🚨the compose in turn is a snapshot WAITED FOR: the '
      'canvas-sized and the positioned one alike', (tester) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );
      final waited = <(int, int)>[];
      debugOnWaitedSnapshot = (width, height) => waited.add((width, height));
      addTearDown(() => debugOnWaitedSnapshot = null);

      final canvasSized = (await composeTiledSurfaceImage(surface))!;
      expect(waited, [(300, 200)], reason: 'what a holder keeps');
      canvasSized.dispose();

      waited.clear();
      final positioned = (await composePositionedSurfaceImage(surface))!;
      expect(waited, [(positioned.image.width, positioned.image.height)]);
      positioned.image.dispose();
    });
  });

  group('positioned compose (pasteboard extent)', () {
    test('surfaceContentWorldRect is the canvas rect without pasteboard '
        'tiles and grows to cover them when present', () {
      // Tile-multiple canvas: the stored grid matches the canvas exactly.
      const canvasSize = CanvasSize(width: 512, height: 256);
      final plain = patternedSurface(canvasSize);
      expect(
        surfaceContentWorldRect(plain),
        const ui.Rect.fromLTRB(0, 0, 512, 256),
      );

      final withPasteboard = plain.putTiles([
        (coord: TileCoord(x: -1, y: -1), tile: BitmapTile.blank(size: 256)),
      ]);
      expect(
        surfaceContentWorldRect(withPasteboard),
        const ui.Rect.fromLTRB(-256, -256, 512, 256),
      );

      // A non-multiple canvas keeps its edge tiles' overhang in the
      // extent — those pixels are drawable pasteboard space now.
      expect(
        surfaceContentWorldRect(
          patternedSurface(const CanvasSize(width: 300, height: 200)),
        ),
        const ui.Rect.fromLTRB(0, 0, 512, 256),
      );
    });

    test('surfaceInkWorldRect counts its grid from the content origin', () {
      // A 2px tile off the canvas's left edge puts the content's origin at
      // x = -2, off the deepest level's 4px grid counted from 0 — the
      // halvings of the whole content line up only counted from -2.
      final surface =
          BitmapSurface(
            canvasSize: const CanvasSize(width: 16, height: 16),
            tileSize: 2,
          ).putTiles([
            (coord: TileCoord(x: -1, y: 0), tile: BitmapTile.blank(size: 2)),
            (coord: TileCoord(x: 4, y: 3), tile: BitmapTile.blank(size: 2)),
          ]);
      expect(
        surfaceContentWorldRect(surface),
        const ui.Rect.fromLTRB(-2, 0, 16, 16),
      );
      expect(
        surfaceInkWorldRect(surface),
        const ui.Rect.fromLTRB(-2, 0, 10, 8),
      );
    });

    testWidgets('a canvas-only surface composes byte-identical to the '
        'canvas-extent route, worldRect = canvas', (tester) async {
      await tester.runAsync(() async {
        // Tile-multiple canvas so the extent equals the canvas exactly.
        final surface = patternedSurface(
          const CanvasSize(width: 512, height: 256),
        );
        final reference = premultipliedCanvasBytes(surface);

        final positioned = (await composePositionedSurfaceImage(surface))!;
        expect(positioned.worldRect, const ui.Rect.fromLTRB(0, 0, 512, 256));
        expect(await bytesOf(positioned.image), reference);
      });
    });

    testWidgets('pasteboard tiles land at their world position in the '
        'grown image', (tester) async {
      await tester.runAsync(() async {
        // One opaque red pixel at world (-256, -256) — the pasteboard
        // tile's own (0, 0).
        final pixels = Uint8List(256 * 256 * 4);
        pixels[0] = 255;
        pixels[3] = 255;
        final surface = BitmapSurface(
          canvasSize: const CanvasSize(width: 300, height: 200),
          tileSize: 256,
          tiles: {
            TileCoord(x: -1, y: -1): BitmapTile(
              size: 256,
              pixels: pixels,
            ),
          },
        );

        final positioned = (await composePositionedSurfaceImage(surface))!;
        expect(positioned.worldRect, const ui.Rect.fromLTRB(-256, -256, 300, 200));
        expect(positioned.image.width, 556);
        expect(positioned.image.height, 456);

        final bytes = await bytesOf(positioned.image);
        // World (-256, -256) → image (0, 0).
        expect(bytes.sublist(0, 4), [255, 0, 0, 255]);
        // World (0, 0) (canvas origin) → image (256, 256): empty here.
        const canvasOrigin = (256 * 556 + 256) * 4;
        expect(bytes.sublist(canvasOrigin, canvasOrigin + 4), [0, 0, 0, 0]);
      });
    });

    // F-374-Q8: a file's picture composed over where it lies cuts through
    // the clear pixels its edge tiles hold — what the part holds is the
    // ink, and every tile is only the cheap proof of that.
    testWidgets('a part composed on its own holds all of the ink: it may '
        'cut through a tile\'s clear pixels, never through its ink', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // One opaque red pixel at (5, 6), alone in its 16px tile.
        final pixels = Uint8List(16 * 16 * 4);
        const at = (6 * 16 + 5) * 4;
        pixels[at] = 255;
        pixels[at + 3] = 255;
        final surface = BitmapSurface(
          canvasSize: const CanvasSize(width: 32, height: 32),
          tileSize: 16,
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile(size: 16, pixels: pixels),
          },
        );

        final part = (await composePositionedSurfaceImage(
          surface,
          over: const ui.Rect.fromLTRB(5, 6, 6, 7),
        ))!;
        expect(part.worldRect, const ui.Rect.fromLTRB(5, 6, 6, 7));
        expect(await bytesOf(part.image), [255, 0, 0, 255]);

        // Each side in turn cuts the one inked pixel off.
        for (final cut in const [
          ui.Rect.fromLTRB(6, 0, 16, 16),
          ui.Rect.fromLTRB(0, 7, 16, 16),
          ui.Rect.fromLTRB(0, 0, 5, 16),
          ui.Rect.fromLTRB(0, 0, 16, 6),
        ]) {
          await expectLater(
            composePositionedSurfaceImage(surface, over: cut),
            throwsAssertionError,
            reason: '$cut',
          );
        }
      });
    });
  });

  testWidgets('shouldAbort stops the compose a picture at a time and '
      'before the final raster (R13-4)', (tester) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );

      // Abort immediately: no tile pictured, no raster, null out.
      expect(
        await composeTiledSurfaceImage(surface, shouldAbort: () => true),
        isNull,
      );

      // Abort partway: the check runs before EVERY transient picture.
      var checks = 0;
      expect(
        await composeTiledSurfaceImage(
          surface,
          shouldAbort: () => ++checks > 1,
        ),
        isNull,
      );
      expect(checks, greaterThan(1));

      // Never aborted: byte-identical to the plain path.
      final aborted = await composeTiledSurfaceImage(
        surface,
        shouldAbort: () => false,
      );
      final plain = await composeTiledSurfaceImage(surface);
      expect(await bytesOf(aborted!), await bytesOf(plain!));
    });
  });

  // BENCHMARK-tagged (skipped by default, see dart_test.yaml): this case
  // compares two WALL-CLOCK measurements, so running it beside the rest of
  // the suite reports CPU contention rather than compose cost. Measured
  // against the CPU assembly it then stood beside: alone 38ms vs 10ms (a
  // 3.8x margin); inside the suite the same code produced 70ms vs 78ms and
  // failed. ↩️Against the cold compose since the CPU assembly left the app
  // (card `cpu-assembly-has-no-caller`): alone 3683ms vs 16ms (Surface,
  // 2026-10-23). Run it deliberately with
  //   flutter test --run-skipped --tags benchmark
  testWidgets('warm compose skips every upload (documented timing)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 1920, height: 1080),
      );

      // A frame no tile of which has a picture — every block uploaded.
      final coldWatch = Stopwatch()..start();
      (await composeTiledSurfaceImage(surface))!.dispose();
      coldWatch.stop();

      // The editing canvas keeps the active frame's tiles decoded — the
      // post-stroke rebuild is the warm case.
      final cache = BitmapTileImageCache();
      await seedCache(cache, surface);
      final warmWatch = Stopwatch()..start();
      (await composeTiledSurfaceImage(surface, reuse: cache))!.dispose();
      warmWatch.stop();

      // ignore: avoid_print
      print(
        'layer image rebuild @1920x1080 — cold compose (every block '
        'uploaded): ${coldWatch.elapsedMilliseconds}ms, warm per-tile GPU '
        'compose: ${warmWatch.elapsedMilliseconds}ms (active-frame '
        'post-stroke case)',
      );
      expect(
        warmWatch.elapsedMilliseconds,
        lessThanOrEqualTo(coldWatch.elapsedMilliseconds),
      );
    });
  }, tags: 'benchmark');

  testWidgets('🚨no compose waits a decode round for a tile: a missing '
      'picture comes through the door on both roads — the same picture, '
      'nothing kept', (tester) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );
      final awaited = countAwaitedUploads();
      (await uploadRawRgba(Uint8List(4), width: 1, height: 1)).dispose();
      expect(awaited(), 1, reason: 'LIVENESS: an awaited upload is counted');

      // The road in turn — the warm's, a filled-in row's.
      final cache = BitmapTileImageCache();
      final inTurn = await bytesOf(
        (await composeTiledSurfaceImage(surface, reuse: cache))!,
      );
      // The road of a render somebody waits for.
      final atOnce = await bytesOf(
        (await composeTiledSurfaceImage(
          surface,
          reuse: cache,
          missing: MissingTilePictures.madeAtOnce,
        ))!,
      );
      expect(awaited(), 1, reason: 'not one more, on either road');
      expect(atOnce, inTurn);
      expect(
        surface.tiles.values.every((tile) => cache.heldFor(tile) == null),
        isTrue,
        reason: 'the pictures were each compose\'s own, and went with it',
      );

      // The positioned road answers to the same words.
      for (final missing in MissingTilePictures.values) {
        (await composePositionedSurfaceImage(
          surface,
          missing: missing,
        ))!.image.dispose();
      }
      expect(awaited(), 1);
    });
  });

  group('the road in turn gives way', () {
    // A test's clock, moved on a quarter of a run by every check before a
    // picture: the queue's turn comes before the fifth picture, the ninth,
    // the thirteenth.
    var clock = 0;
    final aQuarterOfARun = tilePictureRun.inMicroseconds ~/ 4;
    bool Function() checking(bool Function() abandoned) => () {
      clock += aQuarterOfARun;
      return abandoned();
    };

    // The corpus holds a clock of its own (`flutter_test_config.dart`): it
    // is handed back, not dropped for the wall's.
    int Function()? corpusClock;
    setUp(() {
      clock = 0;
      corpusClock = debugTilePictureClock;
      debugTilePictureClock = () => clock;
    });
    tearDown(() => debugTilePictureClock = corpusClock);

    testWidgets('🚨what was waiting in the event queue is heard before a '
        'compose longer than a run is done — and a compose somebody waits '
        'for does not stop for it', (tester) async {
      await tester.runAsync(() async {
        // One picture more than a run holds: the queue gets its turn once.
        var heard = false;
        Timer.run(() => heard = true);
        expect(
          await composeTiledSurfaceImage(
            rowOfTiles(5),
            shouldAbort: checking(() => heard),
          ),
          isNull,
          reason: 'what was waiting was let in when the run was up, and it '
              'stood the compose down',
        );
        expect(heard, isTrue);

        // A whole run is made before the first giving way.
        clock = 0;
        var heardInARun = false;
        Timer.run(() => heardInARun = true);
        final oneRun = await composeTiledSurfaceImage(
          rowOfTiles(4),
          shouldAbort: checking(() => heardInARun),
        );
        expect(
          oneRun,
          isNotNull,
          reason: 'a run is made in one go: nothing was let in before its '
              'last picture, nor before the raster after it',
        );
        oneRun!.dispose();

        // And the road of a render somebody waits for never gives way.
        clock = 0;
        var heardAtOnce = false;
        Timer.run(() => heardAtOnce = true);
        final atOnce = await composeTiledSurfaceImage(
          rowOfTiles(5),
          missing: MissingTilePictures.madeAtOnce,
          shouldAbort: checking(() => heardAtOnce),
        );
        expect(atOnce, isNotNull);
        atOnce!.dispose();
      });
    });

    testWidgets('once a RUN, not once a picture — the turn the old road '
        'waited for every tile', (tester) async {
      await tester.runAsync(() async {
        // Every turn of the event queue from here on is counted: each one,
        // when it comes, asks for the next.
        var turns = 0;
        var counting = true;
        void count() {
          if (counting) {
            turns += 1;
            Timer.run(count);
          }
        }

        Timer.run(count);
        var turnsAtTheLastCheck = -1;
        final image = await composeTiledSurfaceImage(
          // Three whole runs, and one picture more.
          rowOfTiles(13),
          shouldAbort: checking(() {
            turnsAtTheLastCheck = turns;
            return false;
          }),
        );
        counting = false;
        image!.dispose();
        expect(
          turnsAtTheLastCheck,
          3,
          reason: 'the queue had its turn after each of the three runs, '
              'and at no other picture',
        );
      });
    });

    testWidgets('a run is read off the wall when no test holds the clock: '
        'once a run\'s worth of time has gone by, the queue gets its turn', (
      tester,
    ) async {
      await tester.runAsync(() async {
        debugTilePictureClock = null;
        var heard = false;
        Timer.run(() => heard = true);
        expect(
          await composeTiledSurfaceImage(
            rowOfTiles(2),
            shouldAbort: () {
              // Longer than a run, on the wall — and only ever longer: a
              // machine that stalls here makes the same point.
              final spent = Stopwatch()..start();
              while (spent.elapsed <= tilePictureRun) {}
              return heard;
            },
          ),
          isNull,
          reason: 'the first picture took a run\'s worth of time, so the '
              'queue had its turn before the second',
        );
      });
    });
  });

  testWidgets('a compose whose every tile has its picture is still stood '
      'down before the raster (R13-4)', (tester) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );
      final cache = BitmapTileImageCache();
      await seedCache(cache, surface);
      var checks = 0;
      expect(
        await composeTiledSurfaceImage(
          surface,
          reuse: cache,
          shouldAbort: () {
            checks += 1;
            return true;
          },
        ),
        isNull,
      );
      expect(checks, 1, reason: 'no picture was missing: the one check is '
          'the raster\'s');
    });
  });

  group('🚨a cel nobody has pictured goes up a BLOCK at a time — the same '
      'bytes as a tile at a time (board a-cold-cel-composes-tile-by-tile)', () {
    /// A cel of 128 px tiles at [coords], each tile's pixels its own and
    /// every alpha regime in each — a picture that laid a tile in the wrong
    /// place, or premultiplied it twice, cannot match. Runs of four equal
    /// pixels keep the test runner's straight drawing short.
    BitmapSurface celOf(Iterable<(int, int)> coords) {
      const size = 128;
      return BitmapSurface(
        canvasSize: const CanvasSize(width: 1280, height: 768),
        tiles: {
          for (final (tileX, tileY) in coords)
            TileCoord(x: tileX, y: tileY): BitmapTile(
              size: size,
              pixels: Uint8List(size * size * 4)
                ..setAll(0, [
                  for (var y = 0; y < size; y += 1)
                    for (var x = 0; x < size; x += 1) ...[
                      (x ~/ 4 * 37 + tileX * 11) & 0xFF,
                      (y * 23 + tileY * 7) & 0xFF,
                      ((x ~/ 4) ^ y) & 0xFF,
                      ((x ~/ 4 + y) * 9 + tileX) % 256,
                    ],
                ]),
            ),
        },
      );
    }

    // Whole blocks, one part-filled across a corner (a gap in its picture),
    // a lone tile, and the pasteboard's.
    final coords = [
      for (var y = 0; y < 4; y += 1)
        for (var x = 0; x < 4; x += 1) (x, y),
      (4, 0),
      (5, 1),
      (9, 5),
      (-1, -1),
      (-1, 2),
    ];

    testWidgets('🚨one picture a BLOCK: four tiles are one, a second block a '
        'second', (tester) async {
      await tester.runAsync(() async {
        // The check before each picture, and the one before the raster.
        Future<int> checksFor(BitmapSurface surface) async {
          var checks = 0;
          (await composeTiledSurfaceImage(
            surface,
            shouldAbort: () {
              checks += 1;
              return false;
            },
          ))!.dispose();
          return checks;
        }

        expect(tileBlockEdge, 256);
        expect(await checksFor(celOf([(0, 0), (1, 0), (0, 1), (1, 1)])), 2);
        expect(
          await checksFor(celOf([
            for (var y = 0; y < 2; y += 1)
              for (var x = 0; x < 4; x += 1) (x, y),
          ])),
          3,
        );
      });
    });

    testWidgets('🚨the blocks show what the tiles show — 1:1, canvas-sized '
        'and positioned, against the cel pictured a tile at a time and the '
        'tiles\' own bytes; a block whose tiles all have pictures drawn '
        'from them, one that has some pictured whole', (tester) async {
      await tester.runAsync(() async {
        final surface = celOf(coords);
        final tileAt = surface.tileAt;
        // Every tile of the lone tile's block, and two of the whole block's.
        final reuse = BitmapTileImageCache()
          ..pictureFor(tileAt(TileCoord(x: 9, y: 5))!)
          ..pictureFor(tileAt(TileCoord(x: 0, y: 0))!)
          ..pictureFor(tileAt(TileCoord(x: 3, y: 2))!);

        final reference = premultipliedCanvasBytes(surface);
        expect(
          await bytesOf((await composeTiledSurfaceImage(surface))!),
          reference,
          reason: 'every block cold',
        );
        expect(
          await bytesOf(
            (await composeTiledSurfaceImage(surface, reuse: reuse))!,
          ),
          reference,
          reason: 'some blocks held, one in part',
        );

        final blocks = (await composePositionedSurfaceImage(
          surface,
          reuse: reuse,
        ))!;
        // Every tile pictured on its own first: no block is cold.
        final pictured = BitmapTileImageCache();
        surface.tiles.values.forEach(pictured.pictureFor);
        final tiles = (await composePositionedSurfaceImage(
          surface,
          reuse: pictured,
        ))!;
        expect(blocks.worldRect, tiles.worldRect);
        expect(
          blocks.worldRect,
          const ui.Rect.fromLTRB(-128, -128, 1280, 768),
          reason: 'fixture: the pasteboard\'s tiles grow the content',
        );
        expect(await bytesOf(blocks.image), await bytesOf(tiles.image));
      });
    });
  });
}
