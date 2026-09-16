import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/level_image.dart';

/// 🚨A LEVEL IS AN EXACT HALVING (render round, 안 1, 2026-09-16): every
/// level pixel is the mean of a 2×2 block of the picture above it, on the
/// tester's Skia exactly as on the tablets' Impeller — the one reduction
/// every engine agrees on, which is why the pyramid is built one halving at
/// a time and never by a one-step `medium` reduction.
void main() {
  /// A [width]×[height] image whose pixel (x, y) is [rgba](x, y).
  Future<ui.Image> image(
    int width,
    int height,
    List<int> Function(int x, int y) rgba,
  ) {
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final c = rgba(x, y);
        final o = (y * width + x) * 4;
        pixels[o] = c[0];
        pixels[o + 1] = c[1];
        pixels[o + 2] = c[2];
        pixels[o + 3] = c[3];
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  List<int> at(Uint8List px, int width, int x, int y) {
    final o = (y * width + x) * 4;
    return [px[o], px[o + 1], px[o + 2], px[o + 3]];
  }

  testWidgets('each level pixel is the mean of its 2×2 block', (tester) async {
    await tester.runAsync(() async {
      // Opaque, so premultiplication cannot enter: a 4×4 whose 2×2 blocks
      // are (0,0,0,0 → 0), (255×4 → 255), (0,255,0,255 → 128), (100…).
      final source = await image(4, 4, (x, y) {
        final block = (y ~/ 2) * 2 + (x ~/ 2);
        final v = switch (block) {
          0 => 0,
          1 => 255,
          2 => (x + y).isEven ? 0 : 255,
          _ => 100,
        };
        return [v, v, v, 255];
      });
      final picture = halvingPicture([(image: source, at: ui.Offset.zero)]);
      final level = await picture.toImage(2, 2);
      picture.dispose();
      final px = await bytesOf(level);
      expect(at(px, 2, 0, 0), [0, 0, 0, 255]);
      expect(at(px, 2, 1, 0), [255, 255, 255, 255]);
      expect(
        at(px, 2, 0, 1),
        [128, 128, 128, 255],
        reason: 'two black and two white texels average to mid-grey — '
            'nearest would have picked one of them',
      );
      expect(at(px, 2, 1, 1), [100, 100, 100, 255]);
    });
  });

  testWidgets('an odd edge keeps its last texel whole: the level is ⌈w/2⌉ '
      'and maps back at exactly half', (tester) async {
    await tester.runAsync(() async {
      expect(halvedSize(2341, 1655), (width: 1171, height: 828));
      expect(sizeAtLevel(2341, 1655, 2), (width: 586, height: 414));
      // 3×2: the third column has no right-hand neighbour; clamped, its
      // level pixel is the texel itself.
      final source = await image(3, 2, (x, y) => [x * 100, 0, 0, 255]);
      final picture = halvingPicture([(image: source, at: ui.Offset.zero)]);
      final level = await picture.toImage(2, 1);
      picture.dispose();
      final px = await bytesOf(level);
      expect(at(px, 2, 0, 0), [50, 0, 0, 255], reason: 'mean of 0 and 100');
      expect(
        at(px, 2, 1, 0),
        [200, 0, 0, 255],
        reason: 'the odd edge: 200 clamped against itself, not half-covered',
      );
    });
  });
}
