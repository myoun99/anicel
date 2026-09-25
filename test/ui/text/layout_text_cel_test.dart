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

import '../../helpers/app_faces.dart';

void main() {
  const canvas = CanvasSize(width: 400, height: 300);

  // 유저 2026-09-25: 「글꼴 앱에서 정한거 통일하는거 해주고」 — a text with no
  // chosen face prints in the app's bundled one, not in whatever the OS
  // hands the engine.
  testWidgets('a text with no chosen face sets in the app\'s face', (
    tester,
  ) async {
    await loadTheAppFaces();
    final layout = layoutTextCel(
      content: const TextCelContent(
        text: 'iiii',
        style: TextCelStyle(fontSize: 20),
      ),
      canvas: canvas,
    );
    addTearDown(layout.dispose);
    // The test's own font sets every glyph one em wide — 80 here; the app's
    // face sets an i narrow.
    expect(layout.textSize.width, lessThan(40));
  });

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
