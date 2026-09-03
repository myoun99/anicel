// EXPANDING A FILL BY ONE PIXEL ADDS THE RING THAT TOUCHES IT ON A SIDE.
//
// The mutation campaign (2026-09-03) turned the ring test's `||` into `&&`
// — a pixel then had to touch the fill on all four sides, so nothing was
// ever added — and nothing noticed: every fill test ran with expandPx 0.
// This pin runs the expansion on the box the other tests use.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/canvas_flood_fill.dart';

void main() {
  /// A white 8×8 RGB raster with [black] pixels inked.
  Uint8List rasterWithInk(Set<(int, int)> black) {
    final rgb = Uint8List(8 * 8 * 4);
    rgb.fillRange(0, rgb.length, 255);
    for (final (x, y) in black) {
      final base = (y * 8 + x) * 4;
      rgb[base] = 0;
      rgb[base + 1] = 0;
      rgb[base + 2] = 0;
    }
    return rgb;
  }

  /// A closed box outline (2,2)..(5,5) — interior = (3..4, 3..4).
  Set<(int, int)> boxOutline() => {
    for (var x = 2; x <= 5; x += 1) ...{(x, 2), (x, 5)},
    for (var y = 3; y <= 4; y += 1) ...{(2, y), (5, y)},
  };

  int maskAt(FloodFillRegion region, int x, int y) {
    if (x < region.left ||
        y < region.top ||
        x >= region.left + region.width ||
        y >= region.top + region.height) {
      return 0;
    }
    return region.mask[(y - region.top) * region.width + (x - region.left)];
  }

  test('expandPx 1 grows the interior onto the ink ring it touches', () {
    final region = floodFillRegion(
      rgb: rasterWithInk(boxOutline()),
      width: 8,
      height: 8,
      seedX: 3,
      seedY: 3,
      options: const FloodFillOptions(expandPx: 1, antiAlias: false),
    )!;

    expect(
      (region.left, region.top, region.width, region.height),
      (2, 2, 4, 4),
      reason: 'the ring around the 2×2 interior is one pixel wide',
    );
    // The interior stays filled.
    expect(maskAt(region, 3, 3), isNot(0));
    // A ring pixel that touches the interior on a side joins it.
    expect(maskAt(region, 3, 2), isNot(0));
    expect(maskAt(region, 2, 3), isNot(0));
    // The box corner touches the interior only diagonally and stays out.
    expect(maskAt(region, 2, 2), 0);
  });
}
