import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/abr/photoshop_pattern.dart';

/// A Photoshop paper texture becomes a tip mask through THE SAME TAIL every
/// other coverage source uses.
///
/// `brushTipMaskFromPattern` used to fuse its own box downscale and its own
/// centred-square padding into one loop — a third copy of two laws that
/// already had one home each — and nothing pinned either. ARCH-audit-Q7
/// (2026-09-07) settled which filter minifies a coverage map, so this
/// pins that the pattern path reads the same one.
PsPattern _pattern({
  required int width,
  required int height,
  required int Function(int x, int y) luminance,
}) {
  final plane = Uint8List(width * height);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      plane[y * width + x] = luminance(x, y);
    }
  }
  return PsPattern(
    id: 'p',
    name: 'paper',
    width: width,
    height: height,
    luminance: plane,
  );
}

void main() {
  test('dark means paint — coverage is the inverted luminance', () {
    final mask = brushTipMaskFromPattern(
      _pattern(width: 4, height: 4, luminance: (x, y) => x < 2 ? 0 : 255),
      id: 'paper',
    );

    expect(mask.size, 4);
    expect(mask.alpha.sublist(0, 2), everyElement(255));
    expect(mask.alpha.sublist(2, 4), everyElement(0));
  });

  test('a non-square pattern is padded to a centred square', () {
    final mask = brushTipMaskFromPattern(
      _pattern(width: 8, height: 4, luminance: (x, y) => 0),
      id: 'paper',
    );

    expect(mask.size, 8);
    // Two empty rows above, two below, the pattern in the middle.
    expect(mask.alpha.sublist(0, 8), everyElement(0));
    expect(mask.alpha.sublist(2 * 8, 3 * 8), everyElement(255));
    expect(mask.alpha.sublist(7 * 8, 8 * 8), everyElement(0));
  });

  test('🚨an oversized pattern comes down through the shared filter, and '
      'the grain a sampler would drop comes with it', () {
    // Ink on every fourth row of a 1024px paper, reduced 4x. A filter that
    // reads a fixed four taps lands between the lines on three rows out of
    // four and answers "blank paper"; one whose support tracks the
    // reduction reads all four and every row keeps its share.
    const side = maxBrushTipMaskSide * 4;
    final mask = brushTipMaskFromPattern(
      _pattern(
        width: side,
        height: side,
        luminance: (x, y) => y % 4 == 0 ? 0 : 255,
      ),
      id: 'paper',
    );

    expect(mask.size, maxBrushTipMaskSide);
    // The middle column, away from the two edges where coverage genuinely
    // runs out.
    for (var y = 2; y < maxBrushTipMaskSide - 2; y += 1) {
      expect(
        mask.alpha[y * maxBrushTipMaskSide + 128],
        greaterThan(0),
        reason: 'row $y lost the grain it covers',
      );
    }
  });
}
