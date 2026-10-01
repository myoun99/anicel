import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/ui/sheet_painting.dart';

TextStyle _plainFace(
  double size, {
  required bool bold,
  required Color color,
}) => TextStyle(fontSize: size, color: color);

/// A printed picture fills the camera's frame in its slot, never the slot
/// (F-197): a window its camera work made taller holds the camera's shape
/// in its middle, and the rest of the slot is the window's.
void main() {
  testWidgets('a picture in a slot taller than its frame prints in the frame '
      'alone', (tester) async {
    final green = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawPaint(Paint()..color = const Color(0xFF00FF00));
      final drawn = recorder.endRecording();
      final image = await drawn.toImage(16, 9);
      drawn.dispose();
      return image;
    }))!;
    addTearDown(green.dispose);
    const slot = Rect.fromLTWH(0, 0, 32, 60);
    const frame = Rect.fromLTWH(0, 21, 32, 18);
    final recorder = ui.PictureRecorder();
    SheetCanvasPrinter(
      style: _plainFace,
      images: SheetMarkImages(pictureFor: (_, _) => green),
    ).paint(
      ui.Canvas(recorder),
      const Size(32, 60),
      (viewport: null, devicePixelRatio: 1, paper: const Size(32, 60)),
      [
        const SheetPicture(
          SheetPaintLayer.picture,
          cutId: 'c',
          pictureFrame: 0,
          slot: slot,
          frame: frame,
        ),
      ],
    );
    final drawn = recorder.endRecording();
    final pixels = (await tester.runAsync(() async {
      final image = await drawn.toImage(32, 60);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
    drawn.dispose();
    int alpha(int x, int y) => pixels.getUint8((y * 32 + x) * 4 + 3);

    expect(alpha(16, 30), 255, reason: 'the frame is the picture');
    expect(alpha(16, 5), 0, reason: 'above the frame the slot is bare');
    expect(alpha(16, 55), 0, reason: 'and below it');
  });
}
