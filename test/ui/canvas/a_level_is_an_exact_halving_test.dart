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
      expect(halvedSize(1171, 828), (width: 586, height: 414));
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

  testWidgets('an odd height and an odd corner keep their last texel whole '
      'too, wherever the source lands', (tester) async {
    await tester.runAsync(() async {
      // 3×3 landing at (1, 1): the right column, the bottom row and the
      // corner each have no neighbour past the edge.
      final source = await image(3, 3, (x, y) => [x * 100, y * 100, 0, 255]);
      final picture = halvingPicture([
        (image: source, at: const ui.Offset(1, 1)),
      ]);
      final level = await picture.toImage(3, 3);
      picture.dispose();
      final px = await bytesOf(level);
      expect(at(px, 3, 0, 0), [0, 0, 0, 0], reason: 'before its place');
      expect(at(px, 3, 1, 1), [50, 50, 0, 255], reason: 'the even block');
      expect(
        at(px, 3, 2, 1),
        [200, 50, 0, 255],
        reason: 'the odd column: 200 whole, its two rows averaged',
      );
      expect(
        at(px, 3, 1, 2),
        [50, 200, 0, 255],
        reason: 'the odd row: 200 whole, its two columns averaged',
      );
      expect(at(px, 3, 2, 2), [200, 200, 0, 255], reason: 'the odd corner');
    });
  });

  testWidgets('an image one texel wide is its own level column', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await image(1, 3, (x, y) => [0, y * 100, 0, 255]);
      final picture = halvingPicture([(image: source, at: ui.Offset.zero)]);
      final level = await picture.toImage(1, 2);
      picture.dispose();
      final px = await bytesOf(level);
      expect(at(px, 1, 0, 0), [0, 50, 0, 255], reason: 'rows 0 and 1');
      expect(at(px, 1, 0, 1), [0, 200, 0, 255], reason: 'the odd corner');
    });
  });

  testWidgets('an even image is halved by one texture draw, an image with '
      'an odd edge by the shader rect', (tester) async {
    // The two draws make the same bytes, so no picture above can tell them
    // apart — the spy reads which one each source took. On the real app
    // (Impeller GLES, 2026-09-24) 70 tiles halved through shader rects
    // rastered in 111.8 ms against 3.23 as texture draws; an odd image
    // drawn by texture draws moved bytes on the tester's Vulkan.
    await tester.runAsync(() async {
      final even = await image(4, 2, (x, y) => [0, 0, 0, 255]);
      final oddWidth = await image(3, 2, (x, y) => [0, 0, 0, 255]);
      final oddHeight = await image(2, 3, (x, y) => [0, 0, 0, 255]);
      final spy = _SpyCanvas();
      drawHalvings(spy, [
        (image: even, at: const ui.Offset(2, 1)),
        (image: oddWidth, at: ui.Offset.zero),
        (image: oddHeight, at: const ui.Offset(0, 4)),
      ]);
      expect(spy.drawn, [
        (
          'texture',
          const ui.Rect.fromLTWH(0, 0, 4, 2),
          const ui.Rect.fromLTWH(2, 1, 2, 1),
        ),
        ('shader', null, const ui.Rect.fromLTWH(0, 0, 2, 1)),
        ('shader', null, const ui.Rect.fromLTWH(0, 4, 1, 2)),
      ]);
    });
  });
}

/// Records each image draw as (how, from, to); everything else is a no-op.
class _SpyCanvas implements ui.Canvas {
  final List<(String, ui.Rect?, ui.Rect)> drawn = [];

  @override
  void drawImageRect(
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) => drawn.add(('texture', src, dst));

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) => drawn.add((
    paint.shader is ui.ImageShader ? 'shader' : 'fill',
    null,
    rect,
  ));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
