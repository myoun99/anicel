import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
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
        fit: MediaFitMode.stretch,
        tileSize: 64,
      );
      image.dispose();

      final tile = surface.tiles.values.single;
      expect(tile.pixels, expected, reason: 'identity means identity');
    });
  });
}
