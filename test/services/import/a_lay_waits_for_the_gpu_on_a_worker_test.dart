// A lay the engine runs — a picture an import fits, a reference's cel a
// door moves — waits for the GPU on a worker, and its tiles are cut there
// (card a-raster-import-goes-gpu-cpu-gpu-cpu): the isolate that paints
// submits the run and is handed tile blocks, waiting for none of it.
// ↩️It read the run itself: it waited for the GPU, then searched every
// tile for ink and copied each into a tile of its own.
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/guide_geometry.dart' show GuideTransform;
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show debugWaitsHere;

void main() {
  // The road production takes — a REAL worker. The corpus runs every
  // worker's job here (`flutter_test_config.dart`).
  setUp(() => debugWorkersRunHere = false);
  tearDown(() => debugWorkersRunHere = true);

  const width = 300;
  const height = 200;
  const canvas = CanvasSize(width: 260, height: 190);

  /// Each pixel its own colour, and a band clear — so a tile laid wrong,
  /// or one kept that holds no ink, shows.
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final i = (y * width + x) * 4;
      rgba[i] = x * 5 % 256;
      rgba[i + 1] = y * 9 % 256;
      rgba[i + 2] = (x + y) * 3 % 256;
      rgba[i + 3] = x > 140 && x < 220 ? 0 : 255;
    }
  }

  Future<BitmapSurface> laid(GuideTransform placement) => layCelPicture(
    picture: PixelsPicture(rgba, width: width, height: height),
    canvas: canvas,
    placement: placement,
  );

  for (final (how, placement) in [
    ('halved', const GuideTransform(0.5, 0, 0, 0.5, 3, 2)),
    ('grown', const GuideTransform(1.7, 0, 0, 1.7, -41.5, -9.25)),
    ('turned', const GuideTransform(0.6, 0.6, -0.6, 0.6, 140, -20)),
  ]) {
    testWidgets('🎯$how, the isolate that paints waits for none of the GPU '
        '— and the cel is the one it laid when it read the run itself', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final (runs, waits) = (debugLayRuns, debugWaitsHere);
        final ours = await laid(placement);

        expect(debugLayRuns, greaterThan(runs));
        expect(debugWaitsHere, waits, reason: 'a lay waited here');

        debugWorkersRunHere = true;
        final here = await laid(placement);
        expect(ours.tiles, isNotEmpty);
        expect(ours.tiles.keys, unorderedEquals(here.tiles.keys));
        for (final MapEntry(key: coord, value: tile) in here.tiles.entries) {
          expect(
            Uint8List.fromList(ours.tiles[coord]!.pixels),
            orderedEquals(Uint8List.fromList(tile.pixels)),
            reason: '$coord',
          );
        }
      });
    });
  }
}
