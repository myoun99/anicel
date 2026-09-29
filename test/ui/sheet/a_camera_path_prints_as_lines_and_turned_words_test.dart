import 'dart:math' as math;
import 'dart:typed_data';
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

/// A camera's path on a conte picture prints as lines and turned words
/// (유저 2026-09-29/30): its frames and the trails of their corners — a
/// frame the camera turned is no rectangle — and each key's name along its
/// frame's top edge, turned with it.
void main() {
  const size = 40;

  /// [marks] printed on a [size]-square page at a pixel a paper unit.
  Future<ByteData> printedOf(
    WidgetTester tester,
    List<SheetMark> marks,
  ) async {
    final recorder = ui.PictureRecorder();
    const SheetCanvasPrinter(style: _plainFace).paint(
      ui.Canvas(recorder),
      const Size(40, 40),
      (viewport: null, devicePixelRatio: 1, paper: const Size(40, 40)),
      marks,
    );
    final drawn = recorder.endRecording();
    final pixels = (await tester.runAsync(() async {
      final image = await drawn.toImage(size, size);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
    drawn.dispose();
    return pixels;
  }

  int alpha(ByteData pixels, int x, int y) =>
      pixels.getUint8((y * size + x) * 4 + 3);

  const square = [
    Offset(5.5, 5.5),
    Offset(34.5, 5.5),
    Offset(34.5, 34.5),
    Offset(5.5, 34.5),
  ];

  testWidgets('a closed line is an outline through its points — its last '
      'side too — and nothing inside', (tester) async {
    final pixels = await printedOf(tester, [
      const SheetStroke(
        SheetPaintLayer.picture,
        points: square,
        argb: 0xFF3B6D11,
        width: 1,
        closed: true,
      ),
    ]);
    expect(alpha(pixels, 20, 5), greaterThan(200), reason: 'the top side');
    expect(alpha(pixels, 34, 20), greaterThan(200), reason: 'the right side');
    expect(alpha(pixels, 5, 20), greaterThan(200), reason: 'the side that closes it');
    expect(alpha(pixels, 20, 20), 0, reason: 'a line, not a fill');
  });

  testWidgets('an open line leaves its ends apart', (tester) async {
    final pixels = await printedOf(tester, [
      const SheetStroke(
        SheetPaintLayer.picture,
        points: square,
        argb: 0xFF5F5E5A,
        width: 1,
      ),
    ]);
    expect(alpha(pixels, 20, 34), greaterThan(200), reason: 'its last leg');
    expect(alpha(pixels, 5, 20), 0, reason: 'no side back to the start');
  });

  testWidgets('turned words turn about their slot\'s corner, slot and all',
      (tester) async {
    SheetWords wordsTurned(double turn) => SheetWords(
      SheetPaintLayer.picture,
      text: 'MMMM',
      slot: const Rect.fromLTWH(20, 4, 16, 8),
      size: 8,
      argb: 0xFFA32D2D,
      fit: SheetWordsFit.oneLine,
      turn: turn,
    );
    int inkIn(ByteData pixels, Rect box) {
      var ink = 0;
      for (var y = box.top.toInt(); y < box.bottom; y += 1) {
        for (var x = box.left.toInt(); x < box.right; x += 1) {
          ink += alpha(pixels, x, y) > 0 ? 1 : 0;
        }
      }
      return ink;
    }

    const across = Rect.fromLTWH(20, 4, 16, 8);
    const down = Rect.fromLTWH(12, 4, 8, 16);
    final flat = await printedOf(tester, [wordsTurned(0)]);
    expect(inkIn(flat, across), greaterThan(0), reason: 'fixture: ink');
    expect(inkIn(flat, down), 0);

    final turned = await printedOf(tester, [wordsTurned(math.pi / 2)]);
    expect(
      inkIn(turned, down),
      greaterThan(0),
      reason: 'a quarter turn clockwise runs the words down from the corner',
    );
    expect(inkIn(turned, across), 0, reason: 'and none where they lay');
  });
}
