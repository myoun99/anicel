import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/resample/coverage_resample.dart';

/// 🚨MINIFICATION FILTERS IN PROPORTION TO THE REDUCTION.
///
/// This is the whole content of ARCH-audit-Q7. A fixed 4-tap bilinear
/// reads four source pixels whether it is shrinking by two or by eight,
/// so at eight it reads a thirty-second of what it claims to summarise
/// and the rest of the picture is simply not consulted — a checkerboard
/// comes back as noise and a hairline comes back as nothing. A filter
/// whose support tracks the reduction reads all sixty-four, and the
/// answers below are the ones a professional tool gives.
///
/// The fixtures are chosen so the two answer differently: a one-pixel
/// checkerboard (a sampler lands on one parity or the other, a
/// proportional filter averages to the middle) and a one-pixel diagonal (a
/// sampler misses it, a proportional filter keeps its share).
void main() {
  /// `side`×`side`, alternating single pixels — the classic aliasing
  /// fixture, at exactly the frequency reduction destroys.
  Uint8List checkerboard(int side) {
    final out = Uint8List(side * side);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side; x += 1) {
        out[y * side + x] = (x + y).isEven ? 0 : 255;
      }
    }
    return out;
  }

  test('🚨a one-pixel checkerboard averages to the middle at an 8× '
      'reduction — a 4-tap bilinear cannot see that far', () {
    final out = resampleCoverage(
      checkerboard(64),
      width: 64,
      height: 64,
      newWidth: 8,
      newHeight: 8,
    );

    // Interior cells only: the border ones straddle the edge of the image,
    // where coverage really is partly empty.
    for (var y = 1; y < 7; y += 1) {
      for (var x = 1; x < 7; x += 1) {
        expect(
          out[y * 8 + x],
          inInclusiveRange(107, 147),
          reason: 'cell ($x,$y) covers 64 source pixels, half of them ink',
        );
      }
    }
  });

  test('🚨a one-pixel DIAGONAL survives an 8× reduction as its share — '
      'this is the hairline a 4-tap bilinear deletes', () {
    final source = Uint8List(64 * 64);
    for (var i = 0; i < 64; i += 1) {
      source[i * 64 + i] = 255;
    }

    final out = resampleCoverage(
      source,
      width: 64,
      height: 64,
      newWidth: 8,
      newHeight: 8,
    );

    for (var i = 0; i < 8; i += 1) {
      expect(
        out[i * 8 + i],
        greaterThan(0),
        reason: 'the line passes through cell ($i,$i) and must not vanish',
      );
    }
    // And it stayed a line: the far corners never saw ink.
    expect(out[7], 0);
    expect(out[7 * 8], 0);
  });

  test('a 1:1 resize is the identity, byte for byte', () {
    final source = Uint8List.fromList([1, 2, 3, 4, 250, 251, 252, 253]);

    expect(
      resampleCoverage(source, width: 4, height: 2, newWidth: 4, newHeight: 2),
      source,
    );
  });

  test('⛔enlarging reconstructs rather than nearest-neighbouring — the '
      'thumbnail of a tiny tip is not blocky', () {
    // A two-pixel ramp blown up: nearest-neighbour would give two flat
    // runs and nothing between them.
    final out = resampleCoverage(
      Uint8List.fromList([0, 255]),
      width: 2,
      height: 1,
      newWidth: 8,
      newHeight: 1,
    );

    expect(out, hasLength(8));
    final middle = out.sublist(2, 6);
    expect(
      middle.toSet().length,
      greaterThan(2),
      reason: 'a reconstruction has in-between values; a copy has two',
    );
  });

  test('a fully empty coverage map stays empty', () {
    final out = resampleCoverage(
      Uint8List(32 * 32),
      width: 32,
      height: 32,
      newWidth: 8,
      newHeight: 8,
    );

    expect(out, everyElement(0));
  });

  test('a solid interior stays solid — the reduction does not darken what '
      'it did not need to touch', () {
    final source = Uint8List(64 * 64)..fillRange(0, 64 * 64, 255);

    final out = resampleCoverage(
      source,
      width: 64,
      height: 64,
      newWidth: 16,
      newHeight: 16,
    );

    for (var y = 1; y < 15; y += 1) {
      for (var x = 1; x < 15; x += 1) {
        expect(out[y * 16 + x], 255, reason: 'cell ($x,$y) is all ink');
      }
    }
  });
}
