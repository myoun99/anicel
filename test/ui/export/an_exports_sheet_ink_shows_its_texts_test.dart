import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/ui/canvas/chained_picture.dart';
import 'package:anicel/src/ui/export/sheet_ink_picture.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// An export's sheet ink is its surface as a sheet shows it: the drawing
/// with the texts laid over it, premultiplied once (`sheetInkPictureOf`),
/// carrying the chain a picture drawn reduced samples.
///
/// 🚨★★★R9-rest (유저 2026-10-06: 「셀의 그림이랑 정확히 동일」): the tiles'
/// compose laid the texts for every caller; since it left the app
/// (export-on-engine ⑶-2b, 2026-11-12) the ink's picture lays them itself,
/// and this holds it to that.
void main() {
  final drawn = TileCoord(x: 0, y: 0);
  final ink = tileOf({
    (1, 1): [10, 20, 30, 255],
    (2, 1): [200, 100, 50, 120],
  });
  final letters = tileOf({
    (5, 5): [200, 0, 0, 160],
  });

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  testWidgets('the picture is the laid surface\'s pixels premultiplied, '
      'texts and all, carrying its chain', (tester) async {
    await tester.runAsync(() async {
      final surface = drawingOf({drawn: ink}).withTexts([
        textOf(1, plate: {drawn: letters}),
      ]);
      final laid = celSurfaceWithTextsLaid(surface);
      expect(laid, isNot(same(surface)), reason: '⛔fixture: it has a text');
      final canvas = surface.canvasSize;

      final picture = await sheetInkPictureOf(surface);
      try {
        expect((picture.width, picture.height), (canvas.width, canvas.height));
        expect(carriesChain(picture), isTrue, reason: 'a sheet lays it small');
        final bytes = await bytesOf(picture);
        expect(
          bytes,
          premultipliedRgbaCopy(
            bitmapSurfaceRegionPixels(laid, canvas.canvasRegion),
          ),
        );
        final letter = (5 * canvas.width + 5) * 4;
        expect(
          bytes.sublist(letter, letter + 4),
          isNot([0, 0, 0, 0]),
          reason: 'the letters are drawn',
        );
      } finally {
        picture.dispose();
      }
    });
  });
}
