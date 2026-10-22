import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨A row composed over its backdrop rasterises only what the canvas still
/// shows ([drawBlendOverBackdrop]) — its clip, a stroke's patch while one is
/// drawn — and that part lands the bytes the whole would have there.
/// 🔬The whole buffer three times a step put a frame 49ms after its input
/// on the Windows app (10-22), against 12ms with the row normal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(LayerBlendShader.load);

  const side = 64;
  final whole = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());

  /// An opaque image whose every pixel differs from its neighbours.
  Future<ui.Image> imageOf(int seed) {
    final pixels = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i += 1) {
      pixels[i * 4] = (i * 7 + seed) & 0xFF;
      pixels[i * 4 + 1] = (i * 13 + seed * 3) & 0xFF;
      pixels[i * 4 + 2] = (i * 29 + seed * 5) & 0xFF;
      pixels[i * 4 + 3] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      side,
      side,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  /// The bytes the screen gets with the row drawn under [clip] at
  /// [rasterScale].
  Future<Uint8List> landed({
    required Rect clip,
    required double rasterScale,
  }) async {
    final below = await imageOf(11);
    final row = await imageOf(97);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..clipRect(clip);
    drawBlendOverBackdrop(
      canvas: canvas,
      bounds: whole,
      rasterScale: rasterScale,
      paintBackdrop: (into, _) => into.drawImage(below, Offset.zero, Paint()),
      paintSource: (into, _) => into.drawImage(row, Offset.zero, Paint()),
      blendMode: LayerBlendMode.linearBurn,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side, side);
    picture.dispose();
    below.dispose();
    row.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The bytes of [bytes] inside [clip], row by row.
  List<int> inside(Uint8List bytes, Rect clip) => [
    for (var y = clip.top.toInt(); y < clip.bottom.toInt(); y += 1)
      for (var x = clip.left.toInt(); x < clip.right.toInt(); x += 1)
        for (var c = 0; c < 4; c += 1) bytes[(y * side + x) * 4 + c],
  ];

  const clip = Rect.fromLTWH(10, 20, 17, 13);

  test('only the part under the clip is rasterised', () async {
    await landed(clip: clip, rasterScale: 1);
    final plan = debugLastSubtreeRaster!;
    expect(
      (plan.pixelWidth, plan.pixelHeight),
      (17, 13),
      reason: 'the row\'s whole buffer is 64×64 — rasterised whole three '
          'times a step, wherever the stroke was',
    );
  });

  test('the part lands the bytes the whole lands there', () async {
    for (final scale in [1.0, 1.5]) {
      final part = await landed(clip: clip, rasterScale: scale);
      final all = await landed(clip: whole, rasterScale: scale);
      expect(
        inside(part, clip),
        inside(all, clip),
        reason: 'at ×$scale the part samples on the whole\'s grid',
      );
    }
  });
}
