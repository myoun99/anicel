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
      alpha[y * size + x] = (x * 255) ~/ (size - 1);
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

    test('an oversized image is reduced to the library limit, and the '
        'whole picture comes down with it', () async {
      // The decoder's half of the shared "fit, downscale, square" tail —
      // only the cut-piece half had a pin. The source is split along the
      // ROW axis on purpose: a tail that keeps the full-size buffer while
      // claiming the fitted side reads only the first rows, so it would
      // answer "all transparent" here rather than pass by accident.
      const side = maxBrushTipMaskSide * 2;
      final alpha = Uint8List(side * side);
      for (var y = side ~/ 2; y < side; y += 1) {
        alpha.fillRange(y * side, (y + 1) * side, 255);
      }
      final png = await encodeBrushTipImage(
        BrushTipMask(id: 'big', size: side, alpha: alpha),
      );

      final decoded = await decodeBrushTipImage(png, id: 'big');

      expect(decoded.size, maxBrushTipMaskSide);
      // Inside the opaque half and away from every border: still solid.
      expect(
        decoded.alpha.sublist(
          240 * maxBrushTipMaskSide + 4,
          240 * maxBrushTipMaskSide + maxBrushTipMaskSide - 4,
        ),
        everyElement(255),
      );
      expect(
        decoded.alpha.sublist(0, maxBrushTipMaskSide),
        everyElement(0),
      );
    });

    test('⚠️the picture ENDS at the edge of the file — the last row is a '
        'ramp, not a cliff', () async {
      // ARCH-audit-Q7, 2026-09-07. The two filters this replaced clamped
      // the border, so a destination pixel half off the image claimed to
      // be as covered as the source pixel beside it. The shared resampler
      // reads outside as empty (`kResampleOutsideToken`), which for
      // COVERAGE is the true answer: past the edge of the registered image
      // there is no ink. The user's criterion for this change was "the
      // tip's appearance changing is fine".
      const side = maxBrushTipMaskSide * 2;
      const last = maxBrushTipMaskSide - 1;
      final png = await encodeBrushTipImage(
        BrushTipMask(
          id: 'solid',
          size: side,
          alpha: Uint8List(side * side)..fillRange(0, side * side, 255),
        ),
      );

      final decoded = await decodeBrushTipImage(png, id: 'solid');

      expect(decoded.alpha[128 * maxBrushTipMaskSide + 128], 255);
      expect(
        decoded.alpha[last * maxBrushTipMaskSide + 128],
        inExclusiveRange(0, 255),
      );
    });

    test('🚨a stroke that a 4-tap bilinear would drop comes down with its '
        'share of the coverage', () async {
      // The heart of ARCH-audit-Q7. Ink on every fourth row, halved: the
      // fixed 4-tap bilinear this replaced sampled rows 2y and 2y+1, which
      // hold ink only when y is even, so HALF THE LINES came back as zero
      // — the drawing thinned to a comb. A filter whose support tracks the
      // reduction reads all four rows and every destination row keeps a
      // share.
      const side = maxBrushTipMaskSide * 2;
      final alpha = Uint8List(side * side);
      for (var y = 0; y < side; y += 4) {
        alpha.fillRange(y * side, (y + 1) * side, 255);
      }
      final png = await encodeBrushTipImage(
        BrushTipMask(id: 'comb', size: side, alpha: alpha),
      );

      final decoded = await decodeBrushTipImage(png, id: 'comb');

      for (var y = 2; y < maxBrushTipMaskSide - 2; y += 1) {
        expect(
          decoded.alpha[y * maxBrushTipMaskSide + 128],
          greaterThan(0),
          reason: 'row $y lost its share of the lines it covers',
        );
      }
    });
  });

  group('brushTipThumbnailAlpha', () {
    test('is the requested side and averages the source', () async {
      final mask = _sampleMask(size: 64);

      final thumbnail = brushTipThumbnailAlpha(mask, side: 16);

      expect(thumbnail.length, 16 * 16);
      // The source ramps left to right, so the thumbnail has to as well.
      expect(thumbnail[0], lessThan(thumbnail[15]));
      // Cell 15 straddles the edge of the mask, where the coverage really
      // does run out; cell 14 is the last one wholly inside it.
      expect(thumbnail[14], greaterThan(200));
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
      expect(thumbnail, everyElement(greaterThan(0)));
      // Enlarging RECONSTRUCTS now rather than nearest-neighbouring, which
      // is what the predecessor did and said it should not (ARCH-audit-Q7,
      // 2026-09-07): the middle of a solid tip is solid, and only the rim
      // — where the mask itself ends — softens.
      expect(thumbnail[8 * 16 + 8], 255);
    });
  });
}
