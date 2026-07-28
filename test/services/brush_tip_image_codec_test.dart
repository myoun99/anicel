import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_tip_image_codec.dart';

/// A mask with a recognisable gradient plus a hard hole, so a round trip
/// that quantises, premultiplies or flips anything shows up immediately.
BrushTipMask _sampleMask({int size = 8, String id = 'test-tip'}) {
  final alpha = Uint8List(size * size);
  for (var y = 0; y < size; y += 1) {
    for (var x = 0; x < size; x += 1) {
      alpha[y * size + x] = ((x * 255) ~/ (size - 1));
    }
  }
  alpha[0] = 0;
  alpha[size * size - 1] = 255;
  return BrushTipMask(id: id, size: size, alpha: alpha);
}

void main() {
  group('brush tip PNG round trip', () {
    test('encode then decode returns the same alpha, byte for byte', () async {
      final mask = _sampleMask();

      final png = await encodeBrushTipImage(mask);
      final decoded = await decodeBrushTipImage(png, id: 'read-back');

      expect(decoded.size, mask.size);
      expect(decoded.alpha, mask.alpha);
      // The id is the caller's, not the file's — a tip is identified by
      // where it lives in the library.
      expect(decoded.id, 'read-back');
    });

    test('survives a fully opaque mask', () async {
      final alpha = Uint8List.fromList(List<int>.filled(16, 255));
      final mask = BrushTipMask(id: 'solid', size: 4, alpha: alpha);

      final decoded = await decodeBrushTipImage(
        await encodeBrushTipImage(mask),
        id: 'solid',
      );

      expect(decoded.alpha, alpha);
    });

    test('survives a fully transparent mask', () async {
      // Every pixel reads zero through the darkness rule, which is what
      // trips the "no coverage at all" fallback — it must not invert.
      final alpha = Uint8List(16);
      final mask = BrushTipMask(id: 'empty', size: 4, alpha: alpha);

      final decoded = await decodeBrushTipImage(
        await encodeBrushTipImage(mask),
        id: 'empty',
      );

      expect(decoded.alpha, alpha);
    });

    test('writes an actual PNG', () async {
      final png = await encodeBrushTipImage(_sampleMask());

      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  group('brushTipThumbnailAlpha', () {
    test('is the requested side and averages the source', () async {
      final mask = _sampleMask(size: 64);

      final thumbnail = brushTipThumbnailAlpha(mask, side: 16);

      expect(thumbnail.length, 16 * 16);
      // The source ramps left to right, so the thumbnail has to as well.
      expect(thumbnail[0], lessThan(thumbnail[15]));
      expect(thumbnail[15], greaterThan(200));
    });

    test('a mask smaller than the thumbnail still fills every cell', () async {
      // Integer cell arithmetic can hand out empty ranges when upscaling;
      // an empty range would punch holes in the preview.
      final thumbnail = brushTipThumbnailAlpha(
        BrushTipMask(
          id: 'tiny',
          size: 2,
          alpha: Uint8List.fromList([255, 255, 255, 255]),
        ),
        side: 16,
      );

      expect(thumbnail.length, 16 * 16);
      expect(thumbnail.every((value) => value == 255), isTrue);
    });
  });
}
