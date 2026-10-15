import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/services/guide_geometry.dart' show GuideTransform;
import 'package:anicel/src/services/import/raster_cel_import.dart';

/// A 1:1 integer-aligned placement must be a BYTE COPY, not a resample:
/// bicubic (FilterQuality.high) blurs even at identity — a hard black
/// line came back 28/255 gray — and the text bake's contract is that the
/// store pixels ARE the engine render.
void main() {
  testWidgets('an exactly canvas-sized image round-trips through '
      'rasterizeImageToSurface byte-identically', (tester) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 64, height: 64);
      final recorder = ui.PictureRecorder();
      final paint = ui.Canvas(recorder);
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 0, 64, 64),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      // Hard 1px black line — the cubic kernel's favorite victim.
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 31, 64, 1),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(64, 64);
      picture.dispose();
      final expected = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();

      final surface = await rasterizeImageToSurface(
        image: image,
        canvas: canvas,
        placement: fitPlacement(image, canvas, MediaFitMode.stretch),
        tileSize: 64,
      );
      image.dispose();

      final tile = surface.tiles.values.single;
      expect(tile.pixels, expected, reason: 'identity means identity');
    });
  });

  // I-68: the copy is for 1:1 alone — a placement that scales (a fit, a
  // reference's pose) resamples, or a paper drawn twice its size would come
  // out in blocks.
  testWidgets('a SCALED placement resamples — only a 1:1 one copies bytes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 64, height: 64);
      final recorder = ui.PictureRecorder();
      final paint = ui.Canvas(recorder);
      // A hard black | white edge, two pixels across.
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      paint.drawRect(
        const ui.Rect.fromLTWH(1, 0, 1, 1),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(2, 1);
      picture.dispose();

      // Four times its size at a whole-pixel origin: a copy repeats each
      // pixel four times, a resample blends where the two meet.
      final surface = await rasterizeImageToSurface(
        image: image,
        canvas: canvas,
        placement: const GuideTransform(4, 0, 0, 4, 0, 0),
        tileSize: 64,
      );
      image.dispose();

      final pixels = surface.tiles.values.single.pixels;
      final reds = {for (var x = 0; x < 8; x += 1) pixels[(64 + x) * 4]};
      expect(
        reds.length,
        greaterThan(2),
        reason: 'values between black and white — not two blocks',
      );
    });
  });
}
