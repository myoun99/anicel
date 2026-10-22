import 'dart:ui' as ui;

import 'package:anicel/src/ui/canvas/paper_background.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨The app's transparency checker is ONE draw, however much it covers
/// (F-373, 2026-10-17) — and still the cells it always was.
///
/// It was a `drawRect` per grey cell, replayed every frame on Impeller:
/// 94,000 of them under a 4000×3000 picture in the import window, most of
/// a second of raster for every press there.
void main() {
  testWidgets('a picture-sized checker is one draw, not one per cell', (
    tester,
  ) async {
    expect(
      (Canvas canvas) =>
          paintAlphaCheckerboard(canvas, const Rect.fromLTWH(0, 0, 4000, 3000)),
      paintsExactlyCountTimes(#drawRect, 1),
    );
  });

  testWidgets('cells of eight from the origin, grey where row + column is '
      'odd, white elsewhere, hard-edged at every whole zoom — and nothing '
      'outside what it was given', (tester) async {
    // Off the cell grid on every side: the cells stand on the canvas's
    // origin, not on the rect's corner.
    const rect = Rect.fromLTWH(3, 5, 61, 43);
    for (final zoom in [1, 2, 3]) {
      final width = ((rect.right + 4) * zoom).ceil();
      final height = ((rect.bottom + 4) * zoom).ceil();
      final rgba = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(zoom.toDouble());
        paintAlphaCheckerboard(canvas, rect);
        final image = await recorder.endRecording().toImage(width, height);
        try {
          final data = await image.toByteData();
          return data!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      });
      int red(int x, int y) => rgba![(y * width + x) * 4];
      int alpha(int x, int y) => rgba![(y * width + x) * 4 + 3];

      var cells = 0;
      for (var row = 0; row * 8 < rect.bottom; row += 1) {
        for (var column = 0; column * 8 < rect.right; column += 1) {
          final centre = Offset(column * 8 + 4, row * 8 + 4);
          if (!rect.deflate(1).contains(centre)) {
            continue;
          }
          cells += 1;
          expect(
            red((centre.dx * zoom).floor(), (centre.dy * zoom).floor()),
            (row + column).isOdd ? 0xCC : 0xFF,
            reason: 'zoom $zoom, cell ($column, $row)',
          );
        }
      }
      expect(cells, greaterThan(20), reason: 'CONTROL: cells were read');

      // Across a run of cell edges, every pixel is one of the two colours:
      // sampled nearest, as the rects it replaced were laid.
      final y = (20 * zoom).floor();
      final reds = {
        for (var x = (9 * zoom).ceil(); x < ((rect.right - 1) * zoom); x += 1)
          red(x, y),
      };
      expect(reds, {0xCC, 0xFF}, reason: 'zoom $zoom: no edge is smoothed');

      expect(alpha(zoom, zoom), 0, reason: 'zoom $zoom: left of and above');
      expect(
        alpha(width - 1, height - 1),
        0,
        reason: 'zoom $zoom: right of and below',
      );
    }
  });
}
