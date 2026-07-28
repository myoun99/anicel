import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

BitmapTile _gradientTile({required TileCoord coord, int size = 4}) {
  final pixels = Uint8List(size * size * BitmapTile.bytesPerPixel);
  for (var y = 0; y < size; y += 1) {
    for (var x = 0; x < size; x += 1) {
      final offset = (y * size + x) * 4;
      pixels[offset] = (x * 60) % 256;
      pixels[offset + 1] = (y * 60) % 256;
      pixels[offset + 2] = 200;
      // Mix fully transparent, translucent, and opaque alphas so the
      // premultiply conversion is exercised on all three ranges.
      pixels[offset + 3] = x == 0 && y == 0
          ? 0
          : (x == 1 ? 128 : (y == 1 ? 77 : 255));
    }
  }
  return BitmapTile(coord: coord, size: size, pixels: pixels);
}

Future<ui.Image> _awaitDecode(
  BitmapTileImageCache cache,
  BitmapTile tile,
) async {
  cache.ensureDecoded(tile);
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final image = cache.imageFor(tile);
    if (image != null) return image;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Tile image decode did not complete.');
}

Future<Uint8List> _paintPixels(
  BitmapSurfacePainter painter, {
  required int width,
  required int height,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size(width.toDouble(), height.toDouble()));
  final image = await recorder.endRecording().toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return byteData!.buffer.asUint8List();
}

void main() {
  group('BitmapTileImageCache', () {
    test('decodes a tile image once and reuses it by identity', () async {
      final cache = BitmapTileImageCache();
      final tile = _gradientTile(coord: TileCoord(x: 0, y: 0));

      final first = await _awaitDecode(cache, tile);
      cache.ensureDecoded(tile);
      final second = cache.imageFor(tile);

      expect(identical(first, second), isTrue);
      expect(first.width, tile.size);
      expect(first.height, tile.size);
    });

    test('notifies listeners when a decode completes', () async {
      final cache = BitmapTileImageCache();
      final tile = _gradientTile(coord: TileCoord(x: 0, y: 0));
      var notified = 0;
      cache.addListener(() => notified += 1);

      await _awaitDecode(cache, tile);

      expect(notified, 1);
    });

    test(
      'decoded image path paints identical pixels to fallback path',
      () async {
        final tile = _gradientTile(coord: TileCoord(x: 0, y: 0));
        final surface = BitmapSurface(
          canvasSize: CanvasSize(width: 4, height: 4),
          tileSize: 4,
          tiles: {tile.coord: tile},
        );

        // Fallback path: a fresh cache has no decoded image on first paint.
        final fallbackPixels = await _paintPixels(
          BitmapSurfacePainter(
            surface: surface,
            showTransparentBackground: false,
            tileImageCache: BitmapTileImageCache(),
          ),
          width: 4,
          height: 4,
        );

        // Image path: decode first, then paint through the same cache.
        final cache = BitmapTileImageCache();
        await _awaitDecode(cache, tile);
        final imagePixels = await _paintPixels(
          BitmapSurfacePainter(
            surface: surface,
            showTransparentBackground: false,
            tileImageCache: cache,
          ),
          width: 4,
          height: 4,
        );

        expect(imagePixels, fallbackPixels);
      },
    );
  });
}
