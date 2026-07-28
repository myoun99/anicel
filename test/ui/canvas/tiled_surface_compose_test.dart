import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

/// The per-tile GPU compose must be byte-identical to the CPU assembly
/// path ([bitmapSurfaceToImage]) — with and without cache reuse — and turn
/// the post-stroke rebuild into cache-hit draws.
void main() {
  tearDown(() {
    debugUploadOffloadPixelThreshold = null;
  });

  BitmapSurface patternedSurface(CanvasSize canvasSize) {
    var surface = BitmapSurface(canvasSize: canvasSize);
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
        surface = surface.putTile(
          BitmapTile(
            coord: TileCoord(x: tileX, y: tileY),
            size: 256,
            pixels: pixels,
          ),
        );
      }
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
    for (final tile in surface.tiles.values) {
      cache.ensureDecoded(tile);
    }
    while (!cache.allDecoded(surface.tiles.values)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
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
      expect(cold, reference, reason: 'transient-decode path');

      final cache = BitmapTileImageCache();
      await seedCache(cache, surface);
      final warm = await bytesOf(
        (await composeTiledSurfaceImage(surface, reuse: cache))!,
      );
      expect(warm, reference, reason: 'cache-reuse path');
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

      final withPasteboard = plain.putTile(
        BitmapTile.blank(coord: TileCoord(x: -1, y: -1), size: 256),
      );
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
          tiles: {
            TileCoord(x: -1, y: -1): BitmapTile(
              coord: TileCoord(x: -1, y: -1),
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
        final canvasOrigin = (256 * 556 + 256) * 4;
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

      // Abort immediately: no tile decodes, no raster, null out.
      expect(
        await composeTiledSurfaceImage(surface, shouldAbort: () => true),
        isNull,
      );

      // Abort partway: the check runs before EVERY transient decode.
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
}
