@Tags(['impeller'])
library;

import 'dart:async';
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
/// the GPU by the whole extent. So such a fill is clipped and painted
/// ([drawShadedRect]) — which may move no texel.
///
/// ⚠️↩️It was the rect cut to the view first (`6d3aa1172`), and the Windows
/// app laid that rect's texels off its shader: the Surface's canvas stopped
/// following the zoom past 154%. This runner's Vulkan maps a cut rect
/// right, so its pixels cannot see that — the draw is read off the calls
/// ([_SpyCanvas]), and the pixels are read off a PATTERNED picture: the
/// red one before it showed red wherever a texel landed.
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

  /// A page-sized picture whose every texel says where it is.
  const whole = Rect.fromLTWH(0, 0, 2432, 1654);
  late ui.Image page;
  setUpAll(() async {
    final bytes = Uint8List(2432 * 1654 * 4);
    for (var y = 0; y < 1654; y += 1) {
      for (var x = 0; x < 2432; x += 1) {
        final i = (y * 2432 + x) * 4;
        bytes[i] = x % 251;
        bytes[i + 1] = y % 241;
        bytes[i + 2] = (x ~/ 251) * 16 + y ~/ 241;
        bytes[i + 3] = 255;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      2432,
      1654,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    page = await done.future;
  });
  tearDownAll(() => page.dispose());

  ui.ImageShader shaderOf(ui.Image image) => ui.ImageShader(
    image,
    TileMode.clamp,
    TileMode.clamp,
    Float64List(16)
      ..[0] = 1
      ..[5] = 1
      ..[10] = 1
      ..[15] = 1,
    filterQuality: FilterQuality.none,
  );

  int at(Uint8List bytes, int x, int y, int channel) =>
      bytes[(y * view.width.toInt() + x) * 4 + channel];

  // The image laid on the grid against the whole rect its shader fills — the
  // laying the canvas had before any cut, right on this runner at every
  // scale — with the view's centre on the page's middle and on its corner,
  // across the Surface's 152/154% (the pan a fraction off the grid).
  for (final scale in [1.0, 1.52, 1.54, 2.0, 3.0, 7.0]) {
    testWidgets('an image laid on the pixel grid at $scale× keeps every '
        'texel where its shader maps it', (tester) async {
      final shader = shaderOf(page);
      addTearDown(shader.dispose);
      for (final centre in [
        const Offset(1216.3, 827.6),
        const Offset(80.2, 60.7),
      ]) {
        final laid = await render(
          tester,
          (canvas) => drawImageRectOnThePixelGrid(
            canvas,
            page,
            whole,
            whole,
            filterQuality: FilterQuality.none,
            pixelRatio: 1,
          ),
          scale: scale,
          centre: centre,
        );
        final mapped = await render(
          tester,
          (canvas) => canvas.drawRect(
            cutOnThePixelGrid(canvas, whole, 1),
            Paint()
              ..shader = shader
              ..isAntiAlias = false,
          ),
          scale: scale,
          centre: centre,
        );
        expect(laid, mapped, reason: 'centre $centre');
      }
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

  test('a shaded rect is its clip, painted — never a rect a shader fills', () {
    final canvas = _SpyCanvas();
    drawShadedRect(
      canvas,
      whole,
      Paint()
        ..shader = shaderOf(page)
        ..isAntiAlias = false,
    );
    expect(canvas.calls, [
      'save',
      'clipRect $whole antiAlias false',
      'drawPaint',
      'restore',
    ]);
  });

  // Clipped: a clip cutting pixels in part keeps them as the whole rect's
  // fill would, at a scale and a pan that put the picture's own edge inside
  // the view too.
  testWidgets('the clip moves no texel the view keeps', (tester) async {
    final shader = shaderOf(page);
    addTearDown(shader.dispose);
    const clip = Rect.fromLTRB(0.3, 0.7, 199.6, 149.2);
    for (final scale in [1.0, 1.7, 3.0]) {
      final centre = Offset(2432 - 37 / scale, 100.4);
      final clipped = await render(
        tester,
        (canvas) => drawShadedRect(canvas, whole, Paint()..shader = shader),
        scale: scale,
        centre: centre,
        clip: clip,
      );
      final filled = await render(
        tester,
        (canvas) => canvas.drawRect(whole, Paint()..shader = shader),
        scale: scale,
        centre: centre,
        clip: clip,
      );
      expect(clipped, filled, reason: 'at $scale×');
    }
  });
}

/// Records the calls a shaded rect is drawn by; everything else is a no-op.
class _SpyCanvas implements ui.Canvas {
  final List<String> calls = [];

  @override
  void save() => calls.add('save');

  @override
  void restore() => calls.add('restore');

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => calls.add('clipRect $rect antiAlias $doAntiAlias');

  @override
  void drawPaint(Paint paint) => calls.add('drawPaint');

  @override
  void drawRect(Rect rect, Paint paint) => calls.add('drawRect');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
