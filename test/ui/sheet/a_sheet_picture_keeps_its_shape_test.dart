import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/ui/sheet_painting.dart';

/// A picture or a media image — the cover's picture, the company logo, the
/// envelope's 도장 — prints CONTAINED in its box: as large as fits,
/// centred, its own shape kept. Every sheet sets one through
/// `paintSheetImageContained`; stretched to the box, a wide logo would
/// print squashed into a square.
void main() {
  testWidgets('a wide image in a square box keeps its shape: centred, the '
      'box bare above and below it', (tester) async {
    final wide = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawPaint(Paint()..color = const Color(0xFF00FF00));
      final drawn = recorder.endRecording();
      final image = await drawn.toImage(20, 10);
      drawn.dispose();
      return image;
    }))!;
    addTearDown(wide.dispose);

    final recorder = ui.PictureRecorder();
    SheetCanvasPrinter(
      style: (size, {required bold, required color}) =>
          TextStyle(fontSize: size, color: color),
      images: SheetMarkImages(imageFor: (path) => wide),
    ).paint(
      ui.Canvas(recorder),
      const Size(40, 40),
      (viewport: null, devicePixelRatio: 1, paper: const Size(40, 40)),
      const [
        SheetImage(
          SheetPaintLayer.content,
          assetPath: 'logo.png',
          slot: Rect.fromLTWH(0, 0, 40, 40),
        ),
      ],
    );
    final drawn = recorder.endRecording();
    final pixels = (await tester.runAsync(() async {
      final image = await drawn.toImage(40, 40);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
    drawn.dispose();
    int alpha(int x, int y) => pixels.getUint8((y * 40 + x) * 4 + 3);

    // 20×10 contained in 40×40 is 40×20, from y 10 to 30.
    expect(alpha(20, 20), 255, reason: 'the image, in the middle');
    expect(alpha(20, 4), 0, reason: 'bare above it');
    expect(alpha(20, 35), 0, reason: 'bare below it');
  });
}
