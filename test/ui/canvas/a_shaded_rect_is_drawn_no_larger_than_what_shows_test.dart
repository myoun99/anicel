@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/paper_background.dart';

/// 🚨A SHADED RECT IS DRAWN NO LARGER THAN WHAT SHOWS
/// (deep-zoom-blanks-the-canvas, 2026-10-27).
///
/// A rect an image's shader fills went white once it passed 16384 device
/// pixels a side, where `drawImageRect` of the same image stayed whole: a
/// new project's canvas went blank past 670% (its 2432-wide picture) on
/// the Surface, and on the Windows app here at 6.8×. Under that, it cost
/// the GPU by the whole extent. So each such rect is cut to the clip
/// ([drawShadedRect]) — which may move no pixel the clip keeps.
void main() {
  const view = Size(200, 150);

  /// [draw] under a view of [scale] whose centre is the canvas point
  /// [centre], cut to [clip] in the view's pixels.
  Future<Uint8List> render(
    WidgetTester tester,
    void Function(Canvas canvas) draw, {
    required double scale,
    required Offset centre,
    Rect clip = const Rect.fromLTWH(0, 0, 200, 150),
  }) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..clipRect(clip)
        ..translate(
          view.width / 2 - centre.dx * scale,
          view.height / 2 - centre.dy * scale,
        )
        ..scale(scale);
      draw(canvas);
      final image = await recorder.endRecording().toImage(
        view.width.toInt(),
        view.height.toInt(),
      );
      bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      image.dispose();
    });
    return bytes;
  }

  late ui.Image red;
  setUpAll(() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 2432, 200),
      Paint()..color = const Color(0xFFFF0000),
    );
    red = recorder.endRecording().toImageSync(2432, 200);
  });
  tearDownAll(() => red.dispose());

  const whole = Rect.fromLTWH(0, 0, 2432, 200);
  void laid(Canvas canvas) => drawImageRectOnThePixelGrid(
    canvas,
    red,
    whole,
    whole,
    filterQuality: FilterQuality.none,
    pixelRatio: 1,
  );

  int at(Uint8List bytes, int x, int y, int channel) =>
      bytes[(y * view.width.toInt() + x) * 4 + channel];

  for (final scale in [6.0, 7.0, 13.0]) {
    testWidgets('an image laid on the pixel grid at $scale× — '
        '${(2432 * scale).round()} device pixels wide — shows it', (
      tester,
    ) async {
      final bytes = await render(
        tester,
        laid,
        scale: scale,
        centre: whole.center,
      );
      expect(
        [for (var channel = 0; channel < 4; channel += 1)
          at(bytes, 100, 75, channel)],
        [255, 0, 0, 255],
      );
    });
  }

  testWidgets('the checker magnified past the cap still checkers', (
    tester,
  ) async {
    // Cells of 8: at 13× one is 104 pixels, so the view meets two shades.
    final bytes = await render(
      tester,
      (canvas) => paintAlphaCheckerboard(canvas, whole),
      scale: 13,
      centre: const Offset(1216, 100),
    );
    final shades = {
      for (var x = 0; x < view.width; x += 10)
        for (var y = 0; y < view.height; y += 10) at(bytes, x, y, 0),
    };
    expect(shades, containsAll(<int>[0xFF, 0xCC]));
  });

  // ⚠️The test runner's Impeller fills the uncut rect whole — the white is
  // the Windows app's (ANGLE) — so what the rect IS is read off the draw.
  test('the rect a shader fills ends a unit past the clip', () {
    final canvas = _SpyCanvas(const Rect.fromLTRB(1100, 80, 1130, 100));
    drawShadedRect(canvas, whole, Paint());
    expect(canvas.drawn, [const Rect.fromLTRB(1099, 79, 1131, 101)]);
  });

  // The cut lies a unit past the clip: a clip cutting pixels in part keeps
  // them as an uncut rect would, at a scale and a pan that put the image's
  // own edge inside the view too.
  testWidgets('the cut moves no pixel the clip keeps', (tester) async {
    final shader = ui.ImageShader(
      red,
      TileMode.clamp,
      TileMode.clamp,
      Float64List(16)
        ..[0] = 1
        ..[5] = 1
        ..[10] = 1
        ..[15] = 1,
      filterQuality: FilterQuality.none,
    );
    addTearDown(shader.dispose);
    const clip = Rect.fromLTRB(0.3, 0.7, 199.6, 149.2);
    for (final scale in [1.0, 1.7, 3.0]) {
      final centre = Offset(2432 - 37 / scale, 100.4);
      final cut = await render(
        tester,
        (canvas) => drawShadedRect(canvas, whole, Paint()..shader = shader),
        scale: scale,
        centre: centre,
        clip: clip,
      );
      final uncut = await render(
        tester,
        (canvas) => canvas.drawRect(whole, Paint()..shader = shader),
        scale: scale,
        centre: centre,
        clip: clip,
      );
      expect(cut, uncut, reason: 'at $scale×');
    }
  });
}

/// Records every rect drawn under a fixed clip; everything else is a no-op.
class _SpyCanvas implements ui.Canvas {
  _SpyCanvas(this.clip);

  final Rect clip;
  final List<Rect> drawn = [];

  @override
  Rect getLocalClipBounds() => clip;

  @override
  void drawRect(Rect rect, Paint paint) => drawn.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
