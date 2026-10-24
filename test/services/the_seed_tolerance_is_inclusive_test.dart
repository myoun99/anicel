// A PIXEL EXACTLY `tolerance` AWAY FROM THE SEED FILLS; ONE MORE DOES NOT —
// PER LANE, THE COVERAGE AS MUCH AS THE COLOURS, AND THE SAME IN EVERY
// FLOOD.
//
// The plain flood, the close-gap flood and the native wave driver each
// wrote the compare out; this pins the boundary they share (`<=`, not `<`)
// on the Dart references, which the parity suites hold the C kernels to.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/seed_tolerance.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

void main() {
  setUp(() => QaNativeEngine.debugForceDartFallback = true);
  tearDown(() => QaNativeEngine.debugForceDartFallback = false);

  test('pixelWithinTolerance is inclusive on every lane, and any one lane '
      'past it is out', () {
    final rgba = Uint8List.fromList([0, 0, 0, 0, 100, 150, 200, 120]);
    bool within(int r, int g, int b, int a, int tolerance) =>
        pixelWithinTolerance(
          rgba,
          4,
          seedAt(Uint8List.fromList([r, g, b, a]), 0),
          tolerance,
        );

    expect(within(100, 150, 200, 120, 0), isTrue, reason: 'the seed itself');
    expect(within(90, 160, 210, 130, 10), isTrue, reason: '10 on each');
    expect(within(89, 150, 200, 120, 10), isFalse, reason: 'red 11 away');
    expect(within(100, 161, 200, 120, 10), isFalse, reason: 'green 11 away');
    expect(within(100, 150, 189, 120, 10), isFalse, reason: 'blue 11 away');
    expect(
      within(100, 150, 200, 131, 10),
      isFalse,
      reason: 'coverage 11 away — the colours alike, the coverage not',
    );
    expect(within(0, 0, 0, 0, 10), isFalse, reason: 'base 4, not base 0');
  });

  test('a seed reads the coverage lane: a fourth byte past 127 still packs '
      'and compares', () {
    final rgba = Uint8List.fromList([255, 255, 255, 255]);
    expect(
      pixelWithinTolerance(rgba, 0, seedAt(rgba, 0), 0),
      isTrue,
      reason: 'white drawn opaque is its own seed',
    );
    expect(
      pixelWithinTolerance(rgba, 0, seedAt(Uint8List(4), 0), 32),
      isFalse,
      reason: '🚨white ink is not the empty canvas (board F-416)',
    );
  });

  /// An opaque white 8×8 raster whose pixel (4, 3) is [distance] below
  /// white on one [lane].
  Uint8List rasterOffBy(int distance, int lane) {
    final rgba = Uint8List(8 * 8 * 4);
    rgba.fillRange(0, rgba.length, 255);
    rgba[(3 * 8 + 4) * 4 + lane] = 255 - distance;
    return rgba;
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
    for (var lane = 0; lane < 4; lane += 1) {
      test('$name, lane $lane: 32 away fills at tolerance 32, 33 does not',
          () {
        FloodFillRegion fill(int distance) => floodFillRegion(
          rgb: rasterOffBy(distance, lane),
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
