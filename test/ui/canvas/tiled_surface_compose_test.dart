import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

import '../../helpers/awaited_uploads.dart';

/// The per-tile GPU compose must be byte-identical to the CPU assembly
/// path ([bitmapSurfaceToImage]) — with and without cache reuse — and turn
/// the post-stroke rebuild into cache-hit draws.
void main() {
  tearDown(() {
    debugUploadOffloadPixelThreshold = null;
  });

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
  /// picture.
  BitmapSurface rowOfTiles(int count) {
    const size = 8;
    var surface = BitmapSurface(
      canvasSize: CanvasSize(width: size * count, height: size),
      tileSize: size,
    );
    for (var x = 0; x < count; x += 1) {
      surface = surface.putTiles([
        (
          coord: TileCoord(x: x, y: 0),
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

  testWidgets('tile compose is byte-identical to the CPU assembly, with '
      'and without cache reuse', (tester) async {
    await tester.runAsync(() async {
      // Partial edge tiles on both axes.
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );

      debugUploadOffloadPixelThreshold = 1 << 62; // CPU path stays sync
      final reference = await bytesOf(await bitmapSurfaceToImage(surface));

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
      debugUploadOffloadPixelThreshold = 1 << 62; // CPU path stays sync
      final reference = await bytesOf(await bitmapSurfaceToImage(surface));

      final cache = BitmapTileImageCache();
      expect(
        surface.tiles.values.every((tile) => cache.imageFor(tile) == null),
        isTrue,
        reason: 'fixture: nothing has pictured these tiles',
      );
      final now = composeTiledSurfaceImageNow(surface, reuse: cache);
      expect(
        surface.tiles.values.every((tile) => cache.imageFor(tile) != null),
        isTrue,
        reason: 'the pictures it made are the cache\'s: the next compose of '
            'this cel — the next edit — pays for the tiles that changed',
      );
      expect(await bytesOf(now), reference);

      // The positioned road, with the plain snapshot of the same recording.
      // It rasters over the CONTENT extent — these 256px tiles reach past
      // the 300×200 canvas — so its twin is the asynchronous positioned
      // compose, not the canvas-sized reference.
      final later = (await composePositionedSurfaceImage(surface))!;
      final want = await bytesOf(later.image);
      final positioned = composePositionedSurfaceImageSync(
        surface,
        reuse: BitmapTileImageCache(),
        makePictures: true,
        snapshot: true,
      )!;
      expect(positioned.deferred.worldRect, surfaceContentWorldRect(surface));
      expect(positioned.deferred.worldRect, later.worldRect);
      expect(await bytesOf(await positioned.real!), want);
      expect(await bytesOf(positioned.deferred.image), want);

      // And the FREE road refuses rather than makes.
      expect(
        composePositionedSurfaceImageSync(
          surface,
          reuse: BitmapTileImageCache(),
          makePictures: false,
          snapshot: false,
        ),
        isNull,
      );
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
        debugUploadOffloadPixelThreshold = 1 << 62;
        final reference = await bytesOf(await bitmapSurfaceToImage(surface));

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
  });

  testWidgets('shouldAbort stops the compose at tile granularity and '
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
  // the suite reports CPU contention rather than compose cost. Measured:
  // alone it reads 38ms vs 10ms (a 3.8x margin); inside the suite the same
  // code produced 70ms vs 78ms and failed. Run it deliberately with
  //   flutter test --run-skipped --tags benchmark
  testWidgets('warm compose skips every upload (documented timing)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 1920, height: 1080),
      );

      debugUploadOffloadPixelThreshold = 1 << 62;
      final cpuWatch = Stopwatch()..start();
      (await bitmapSurfaceToImage(surface)).dispose();
      cpuWatch.stop();

      // The editing canvas keeps the active frame's tiles decoded — the
      // post-stroke rebuild is the warm case.
      final cache = BitmapTileImageCache();
      await seedCache(cache, surface);
      final warmWatch = Stopwatch()..start();
      (await composeTiledSurfaceImage(surface, reuse: cache))!.dispose();
      warmWatch.stop();

      // ignore: avoid_print
      print(
        'layer image rebuild @1920x1080 — CPU assembly+upload: '
        '${cpuWatch.elapsedMilliseconds}ms, warm per-tile GPU compose: '
        '${warmWatch.elapsedMilliseconds}ms (active-frame post-stroke case)',
      );
      expect(
        warmWatch.elapsedMilliseconds,
        lessThanOrEqualTo(cpuWatch.elapsedMilliseconds),
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
        surface.tiles.values.every((tile) => cache.imageFor(tile) == null),
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

    setUp(() {
      clock = 0;
      debugTilePictureClock = () => clock;
    });
    tearDown(() => debugTilePictureClock = null);

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
}
