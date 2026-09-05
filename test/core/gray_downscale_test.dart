import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/gray_downscale.dart';

/// 🚨THE FOOTPRINT IS AVERAGED, NOT SAMPLED.
///
/// A destination pixel covers a BLOCK of source pixels, and a downscale
/// that reads only one of them drops whole strokes out of thin line art —
/// the failure `resample_kernel.dart` names for point sampling under
/// reduction. A tip mask is coverage, so a pixel that is half covered has
/// to come out half covered.
void main() {
  Uint8List gray(List<int> values) => Uint8List.fromList(values);

  test('🚨alternating COLUMNS average to the middle — a sampler would '
      'return one of the two extremes', () {
    // 4x2, columns 0/255/0/255. Halving the width puts one dark and one
    // light column under every destination pixel.
    final out = areaAveragedGray(
      gray([0, 255, 0, 255, 0, 255, 0, 255]),
      width: 4,
      height: 2,
      newWidth: 2,
      newHeight: 2,
    );

    expect(out, [127, 127, 127, 127]);
  });

  test('🚨alternating ROWS average the same way', () {
    // 2x4, rows 0/255/0/255.
    final out = areaAveragedGray(
      gray([0, 0, 255, 255, 0, 0, 255, 255]),
      width: 2,
      height: 4,
      newWidth: 2,
      newHeight: 2,
    );

    expect(out, [127, 127, 127, 127]);
  });

  test('a lone bright pixel SURVIVES as its share of the block — this is '
      'the thin stroke a sampler loses', () {
    final source = Uint8List(16); // 4x4 of black
    source[5] = 255; // one pixel inside the top-left 2x2 block

    final out = areaAveragedGray(
      source,
      width: 4,
      height: 4,
      newWidth: 2,
      newHeight: 2,
    );

    expect(out[0], 63, reason: '255 over four pixels');
    expect(out.skip(1), everyElement(0));
  });

  test('a 1:1 resize is the identity', () {
    final source = gray([1, 2, 3, 4]);

    expect(
      areaAveragedGray(source, width: 2, height: 2, newWidth: 2, newHeight: 2),
      [1, 2, 3, 4],
    );
  });

  test('⛔a destination pixel never has an EMPTY box — the width is what '
      'keeps a degenerate block from reading nothing', () {
    // More destination pixels than source ones: every one still names at
    // least one source pixel rather than dividing by zero.
    final out = areaAveragedGray(
      gray([10, 20]),
      width: 2,
      height: 1,
      newWidth: 4,
      newHeight: 1,
    );

    expect(out, hasLength(4));
    expect(out, everyElement(isNot(0)));
  });
}
