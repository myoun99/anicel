@Tags(['impeller'])
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/sync_image_upload.dart' show pictureOfUploads;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';

/// 🚨★★★A SURFACE DRAWN REDUCED IS ITS ONE PICTURE DRAWN REDUCED — at 1/2ⁿ
/// to the byte (one-picture-per-frame ②-5b-2, 유저 D7-2-Q2 「배율이 어떻든
/// 항상 원본 한장」).
///
/// The one picture is a render of the surface at 100%, which the engine
/// gives its mip chain; the surface's painter draws each tile from its own
/// picture remade with that chain (`chained_picture.dart`), so both are the
/// engine's halvings on one grid. 🔬Measured on the real Windows app
/// (Impeller OpenGLES) and here on the tester's Vulkan: 0 apart at 1/2, 1/4
/// and 1/8; drawn from the door's uploads instead, which carry no chain,
/// nearly every pixel apart at 1/4 — the scene proves it can tell.
///
/// Only an engine whose door UPLOADS can tell a chain from none: the
/// tester's Skia chains a door picture by itself. So this runs on the
/// Impeller tester (`flutter test --enable-impeller`, the `impeller` tag's
/// batch) and skips on Skia, and says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const side = 128;
  const tileSize = 32;
  const canvasSize = CanvasSize(width: side, height: side);

  /// Line work that changes every few pixels, some of it partly clear.
  List<int> inkAt(int x, int y) {
    if ((x * 7 + y * 13) % 11 == 0 || (x - y).abs() < 1 || x % 9 == 0) {
      return [20, 30, 40, 255];
    }
    final r = math.sqrt(math.pow(x - 64.0, 2) + math.pow(y - 64.0, 2));
    if ((r - 40).abs() < 2) {
      return [200, 40, 40, ((2 - (r - 40).abs()) / 2 * 255).round()];
    }
    return [0, 0, 0, 0];
  }

  final tiles = <TileCoord, BitmapTile>{
    for (var ty = 0; ty < side ~/ tileSize; ty += 1)
      for (var tx = 0; tx < side ~/ tileSize; tx += 1)
        TileCoord(x: tx, y: ty): () {
          final pixels = Uint8List(tileSize * tileSize * 4);
          for (var y = 0; y < tileSize; y += 1) {
            for (var x = 0; x < tileSize; x += 1) {
              pixels.setAll(
                (y * tileSize + x) * 4,
                inkAt(tx * tileSize + x, ty * tileSize + y),
              );
            }
          }
          return BitmapTile(size: tileSize, pixels: pixels);
        }(),
  };

  Future<Uint8List> raster(void Function(ui.Canvas) paint, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawRect(
        ui.Rect.fromLTWH(0, 0, size * 1.0, size * 1.0),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    image.dispose();
    return bytes;
  }

  int apart(Uint8List a, Uint8List b) {
    var count = 0;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        count += 1;
      }
    }
    return count;
  }

  final skip = pictureOfUploads
      ? false
      : 'the door draws here (Skia), and Skia chains its pictures itself';

  for (final zoom in [0.5, 0.25, 0.125]) {
    test('at $zoom the surface\'s painter draws its one picture\'s '
        'bytes', () async {
      final cache = BitmapTileImageCache();
      final recorder = ui.PictureRecorder();
      final whole = ui.Canvas(recorder);
      for (final MapEntry(key: coord, value: tile) in tiles.entries) {
        whole.drawImage(
          cache.pictureFor(tile).image,
          ui.Offset(coord.x * tileSize * 1.0, coord.y * tileSize * 1.0),
          ui.Paint()..filterQuality = ui.FilterQuality.none,
        );
      }
      final made = recorder.endRecording();
      final onePicture = await made.toImage(side, side);
      made.dispose();

      final viewport = CanvasViewport(zoom: zoom);
      final size = (side * zoom).round();
      final ofOne = await raster((canvas) {
        applyViewportTransform(canvas, viewport);
        drawOnTheDisplay(
          canvas,
          onePicture,
          const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
          const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
          viewport: viewport,
          devicePixelRatio: 1,
        );
      }, size);
      final unchained = await raster((canvas) {
        applyViewportTransform(canvas, viewport);
        for (final MapEntry(key: coord, value: tile) in tiles.entries) {
          canvas.drawImage(
            BitmapTileImageCache.pictureOfTile(tile),
            ui.Offset(coord.x * tileSize * 1.0, coord.y * tileSize * 1.0),
            ui.Paint()..filterQuality = filterQualityForDisplayScale(zoom),
          );
        }
      }, size);
      final painted = await raster(
        (canvas) => BitmapSurfacePainter(
          surface: BitmapSurface(
            canvasSize: canvasSize,
            tileSize: tileSize,
            tiles: tiles,
          ),
          viewport: viewport,
          showTransparentBackground: false,
          lineage: 'one-picture-at-$zoom',
          tileImageCache: cache,
        ).paint(canvas, ui.Size(size * 1.0, size * 1.0)),
        size,
      );
      onePicture.dispose();

      if (zoom <= 0.25) {
        expect(
          apart(unchained, ofOne),
          greaterThan(size * size),
          reason: '⛔premise: drawn from the uploads, the scene tells',
        );
      }
      expect(apart(painted, ofOne), 0);
    }, skip: skip);
  }
}
