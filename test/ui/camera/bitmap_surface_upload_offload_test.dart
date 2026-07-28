import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';

/// The upload-buffer assembly (straight-alpha tiles → premultiplied rgba)
/// offloads to an isolate on canvas-sized surfaces; small surfaces stay on
/// the synchronous path. Both must be byte-identical.
void main() {
  tearDown(() {
    debugUploadOffloadPixelThreshold = null;
  });

  /// A surface whose tiles carry every alpha regime (0 / mid / 255) plus
  /// partial edge tiles, so the premultiply branches all execute.
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
          // Cycles through 0, mid values and 255.
          pixels[index + 3] = (pixel * 5) % 256;
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

  Future<Uint8List> renderedBytes(BitmapSurface surface) async {
    final image = await bitmapSurfaceToImage(surface);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  testWidgets('the isolate-assembled upload is byte-identical to the '
      'synchronous path', (tester) async {
    await tester.runAsync(() async {
      // Partial edge tiles on both axes.
      final surface = patternedSurface(
        const CanvasSize(width: 300, height: 200),
      );

      debugUploadOffloadPixelThreshold = 1 << 62; // force sync
      final synchronous = await renderedBytes(surface);

      debugUploadOffloadPixelThreshold = 0; // force the isolate
      final offloaded = await renderedBytes(surface);

      expect(offloaded, synchronous);
    });
  });

  // BENCHMARK-tagged (skipped by default, see dart_test.yaml): this case
  // asserts nothing — it assembles 1920x1080 TWICE just to print the two
  // wall-clock numbers, which is benchmark work, not a regression test. The
  // isolate path keeps its correctness coverage in the byte-identical case
  // above. Run it with: flutter test --run-skipped --tags benchmark
  testWidgets('canvas-sized surfaces take the isolate path by default '
      '(documented timing)', (tester) async {
    await tester.runAsync(() async {
      final surface = patternedSurface(
        const CanvasSize(width: 1920, height: 1080),
      );

      // 1920×1080 ≥ the default threshold — no override, real path.
      final offloadWatch = Stopwatch()..start();
      final viaIsolate = await bitmapSurfaceToImage(surface);
      offloadWatch.stop();
      viaIsolate.dispose();

      debugUploadOffloadPixelThreshold = 1 << 62;
      final syncWatch = Stopwatch()..start();
      final viaUiThread = await bitmapSurfaceToImage(surface);
      syncWatch.stop();
      viaUiThread.dispose();

      // ignore: avoid_print
      print(
        'bitmapSurfaceToImage @1920x1080 — fully on the calling thread: '
        '${syncWatch.elapsedMilliseconds}ms (this chunk used to block the '
        'UI); via isolate: ${offloadWatch.elapsedMilliseconds}ms wall, '
        'calling thread only snapshots tiles + decodes',
      );
    });
  }, tags: 'benchmark');
}
