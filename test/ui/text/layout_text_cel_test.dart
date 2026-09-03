// A TEXT CEL LAYS OUT WITH REAL INK BOUNDS INSIDE ITS CANVAS, AND PAINTS.
//
// No test named the text cel renderer (audit 2026-09-03). These pins ask
// the layout for the facts the text tool reads — a non-empty size, ink
// bounds that sit on the canvas — and paint it once so a broken painter
// pair would throw here rather than on a canvas.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/text_cel_render.dart';

void main() {
  const canvas = CanvasSize(width: 400, height: 300);

  testWidgets('a short line has ink inside the canvas', (tester) async {
    final layout = layoutTextCel(
      content: const TextCelContent(text: 'Hello'),
      canvas: canvas,
    );
    addTearDown(layout.dispose);
    expect(layout.textSize.width, greaterThan(0));
    expect(layout.textSize.height, greaterThan(0));
    expect(layout.inkBounds.isEmpty, isFalse);
    expect(layout.inkBounds.left, greaterThanOrEqualTo(0));
    expect(layout.inkBounds.top, greaterThanOrEqualTo(0));
    expect(layout.inkBounds.right, lessThanOrEqualTo(canvas.width));
    expect(layout.inkBounds.bottom, lessThanOrEqualTo(canvas.height));
  });

  testWidgets('a bigger font lays out bigger', (tester) async {
    final small = layoutTextCel(
      content: const TextCelContent(
        text: 'Hello',
        style: TextCelStyle(fontSize: 24),
      ),
      canvas: canvas,
    );
    addTearDown(small.dispose);
    final big = layoutTextCel(
      content: const TextCelContent(
        text: 'Hello',
        style: TextCelStyle(fontSize: 72),
      ),
      canvas: canvas,
    );
    addTearDown(big.dispose);
    expect(big.textSize.width, greaterThan(small.textSize.width));
    expect(big.textSize.height, greaterThan(small.textSize.height));
  });

  testWidgets('the layout paints, with and without a background', (
    tester,
  ) async {
    for (final style in const [
      TextCelStyle(),
      TextCelStyle(backgroundColor: 0xFFFFFF00, outlineWidth: 2),
    ]) {
      final layout = layoutTextCel(
        content: TextCelContent(text: 'Hi', style: style),
        canvas: canvas,
      );
      final recorder = ui.PictureRecorder();
      layout.paint(ui.Canvas(recorder));
      recorder.endRecording().dispose();
      layout.dispose();
    }
  });
}
