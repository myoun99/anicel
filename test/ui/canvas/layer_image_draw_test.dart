import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Evidence for the one flag in `drawPosedLayerImage`.
///
/// Two of the three routes have always drawn their canvas-extent images
/// with `drawImage(Offset.zero)` while the third uses `drawImageRect`, and
/// their pixels are pinned by composite parity suites. The convergence
/// therefore kept a `drawAtOrigin` flag rather than assume Skia lowers the
/// two identically — the repo's rule being to measure rather than reason
/// about the backend.
///
/// This is that measurement. If it says the two agree, the flag can be
/// retired with a citation. If it ever stops saying so, the flag was
/// load-bearing all along and this test records why.
void main() {
  Future<ui.Image> decode(int width, int height) async {
    final bytes = Uint8List(width * height * 4);
    final words = Uint32List.view(bytes.buffer);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        // Hard-edged blocks and a diagonal: a gradient would hide a
        // half-pixel offset, which is exactly what could differ.
        final ink = ((x ~/ 3) + (y ~/ 3)).isEven || x == y;
        words[y * width + x] = ink ? 0xff102030 : 0xffe0e8f0;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<Uint8List> render(
    ui.Image image,
    void Function(ui.Canvas canvas, ui.Paint paint) draw,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.low
      ..color = const ui.Color.fromRGBO(0, 0, 0, 0.6);
    draw(canvas, paint);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(image.width, image.height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    rendered.dispose();
    return data!.buffer.asUint8List();
  }

  test('drawImage(Offset.zero) and the equivalent drawImageRect agree, so '
      'the drawAtOrigin flag is a pin and not a requirement', () async {
    final image = await decode(24, 18);
    final whole = await render(
      image,
      (canvas, paint) => canvas.drawImage(image, ui.Offset.zero, paint),
    );
    final rect = await render(
      image,
      (canvas, paint) => canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        paint,
      ),
    );
    image.dispose();
    expect(rect, whole);
  });
}
