// A PIXEL EXACTLY `tolerance` AWAY FROM THE SEED FILLS; ONE MORE DOES NOT —
// PER CHANNEL, AND THE SAME IN EVERY FLOOD.
//
// The plain flood, the close-gap flood and the native wave driver each
// wrote the three-channel compare out; this pins the boundary they share
// (`<=`, not `<`) on the Dart references, which the parity suites hold the
// C kernels to.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/rgb_tolerance.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

void main() {
  setUp(() => QaNativeEngine.debugForceDartFallback = true);
  tearDown(() => QaNativeEngine.debugForceDartFallback = false);

  test('rgbWithinTolerance is inclusive on every channel, and any one '
      'channel past it is out', () {
    final rgb = Uint8List.fromList([0, 0, 0, 0, 100, 150, 200, 0]);
    bool within(int r, int g, int b, int tolerance) =>
        rgbWithinTolerance(rgb, 4, r, g, b, tolerance);

    expect(within(100, 150, 200, 0), isTrue, reason: 'the seed itself');
    expect(within(90, 160, 210, 10), isTrue, reason: 'exactly 10 on each');
    expect(within(89, 150, 200, 10), isFalse, reason: 'red 11 away');
    expect(within(100, 161, 200, 10), isFalse, reason: 'green 11 away');
    expect(within(100, 150, 189, 10), isFalse, reason: 'blue 11 away');
    expect(within(0, 0, 0, 10), isFalse, reason: 'base 4, not base 0');
  });

  /// A white 8×8 raster whose pixel (4, 3) is [distance] below white on
  /// one [channel].
  Uint8List rasterOffBy(int distance, int channel) {
    final rgb = Uint8List(8 * 8 * 4);
    rgb.fillRange(0, rgb.length, 255);
    rgb[(3 * 8 + 4) * 4 + channel] = 255 - distance;
    return rgb;
  }

  int maskAt(FloodFillRegion region, int x, int y) {
    if (x < region.left ||
        y < region.top ||
        x >= region.left + region.width ||
        y >= region.top + region.height) {
      return 0;
    }
    return region.mask[(y - region.top) * region.width + (x - region.left)];
  }

  for (final (name, gapClosePx) in [
    ('plain flood', 0),
    ('close-gap flood', 2),
  ]) {
    for (var channel = 0; channel < 3; channel += 1) {
      test('$name, channel $channel: 32 away fills at tolerance 32, 33 does '
          'not', () {
        FloodFillRegion fill(int distance) => floodFillRegion(
          rgb: rasterOffBy(distance, channel),
          width: 8,
          height: 8,
          seedX: 3,
          seedY: 3,
          options: FloodFillOptions(
            tolerance: 32,
            expandPx: 0,
            antiAlias: false,
            gapClosePx: gapClosePx,
          ),
        )!;

        expect(maskAt(fill(32), 4, 3), 255, reason: 'inclusive');
        expect(maskAt(fill(33), 4, 3), 0, reason: 'one past is out');
      });
    }
  }
}
