import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

/// R14-② fill performance instrument: a large enclosed region (the user's
/// real case — filling a background/figure on a big canvas) with the
/// ensure-composed callback counted. Print-only timings plus structural
/// pins on the callback volume: the tap used to invoke it PER VISITED
/// PIXEL (tens of millions of dynamic calls = the multi-second freeze).
///
/// NOT tagged `benchmark`: the tag skips the whole file, and the callback
/// -volume pin below is a FREEZE GUARD whose own comment says the pixel-
/// volume call counts "must never come back". A guard that does not run
/// is not a guard. It counts calls, which the clock cannot move.
void main() {
  test('large-region fill: timing + ensureComposed call volume', () {
    const width = 1600;
    const height = 1600;
    // White canvas with a black border ring — seed center fills the whole
    // interior (~2.5M pixels).
    final rgb = Uint8List(width * height * 4);
    for (var i = 0; i < rgb.length; i += 1) {
      rgb[i] = 255;
    }
    void ink(int x, int y) {
      final base = (y * width + x) * 4;
      rgb[base] = 0;
      rgb[base + 1] = 0;
      rgb[base + 2] = 0;
    }

    for (var x = 0; x < width; x += 1) {
      ink(x, 0);
      ink(x, height - 1);
    }
    for (var y = 0; y < height; y += 1) {
      ink(0, y);
      ink(width - 1, y);
    }

    var ensureCalls = 0;
    final watch = Stopwatch()..start();
    final region = floodFillRegion(
      rgb: rgb,
      width: width,
      height: height,
      seedX: width ~/ 2,
      seedY: height ~/ 2,
      ensureComposed: (_) => ensureCalls += 1,
    )!;
    watch.stop();

    final filled = region.mask.where((v) => v != 0).length;
    // ignore: avoid_print
    print(
      'flood fill ${width}x$height interior: ${watch.elapsedMilliseconds}ms, '
      'filled≈$filled px, ensureComposed calls $ensureCalls',
    );

    expect(filled, greaterThan(2_000_000), reason: 'the interior filled');
    // The callback must be tile-granular, not pixel-granular: for a 1600²
    // canvas there are only 49 (7×7) 256px tiles — allow generous slack
    // for boundary-crossing re-ensures, but pixel-volume call counts
    // (millions) are the freeze and must never come back.
    expect(
      ensureCalls,
      lessThan(100000),
      reason: 'ensureComposed fires per tile crossing, never per pixel',
    );
  });
}
