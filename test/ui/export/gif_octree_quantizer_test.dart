import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anicel/src/ui/export/gif_octree_quantizer.dart';

/// 🗣️I-152 (AI check 2026-11-04): 「빨강 획까지 전부 파랑」 · 「획이 통째로
/// 없다」 — the palette an octree keeps, and which colours give way first.
void main() {
  /// A picture one pixel high of each colour, as many times as it says.
  img.Image pictureOf(List<((int, int, int), int)> colours) {
    final width = colours.fold(0, (sum, colour) => sum + colour.$2);
    final picture = img.Image(width: width, height: 1);
    var x = 0;
    for (final ((r, g, b), times) in colours) {
      for (var i = 0; i < times; i += 1) {
        picture.setPixelRgb(x, 0, r, g, b);
        x += 1;
      }
    }
    return picture;
  }

  Set<(int, int, int)> paletteOf(GifOctreeQuantizer quantizer) => {
    for (var index = 0; index < quantizer.palette.numColors; index += 1)
      (
        quantizer.palette.getRed(index).toInt(),
        quantizer.palette.getGreen(index).toInt(),
        quantizer.palette.getBlue(index).toInt(),
      ),
  };

  test('the thinnest branch folds first, so the colours most pixels wear '
      'stay apart', () {
    final quantizer = GifOctreeQuantizer(
      pictureOf([
        ((200, 0, 0), 1000),
        ((201, 0, 0), 1000),
        ((0, 0, 200), 1),
        ((0, 0, 201), 1),
      ]),
      colors: 3,
    );

    expect(paletteOf(quantizer), {(200, 0, 0), (201, 0, 0), (0, 0, 201)});
  });

  test('a colour the palette holds is its own entry, not the nearest to '
      'its cell', () {
    final quantizer = GifOctreeQuantizer(
      pictureOf([
        ((200, 0, 0), 1000),
        ((201, 0, 0), 1000),
        ((0, 0, 200), 1),
        ((0, 0, 201), 1),
      ]),
      colors: 3,
    );

    final index = quantizer.getColorIndexRgb(200, 0, 0);
    expect(
      (
        quantizer.palette.getRed(index).toInt(),
        quantizer.palette.getGreen(index).toInt(),
        quantizer.palette.getBlue(index).toInt(),
      ),
      (200, 0, 0),
    );
  });

  test('a fold that would leave fewer than asked is left to the merge, '
      'which takes the thinnest into its nearest', () {
    final quantizer = GifOctreeQuantizer(
      pictureOf([
        ((0, 0, 0), 1),
        ((0, 0, 2), 1),
        ((0, 2, 0), 5),
        ((255, 255, 255), 100),
      ]),
      colors: 3,
    );

    expect(paletteOf(quantizer), {(0, 0, 1), (0, 2, 0), (255, 255, 255)});
  });
}
