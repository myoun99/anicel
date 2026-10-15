import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

import '../helpers/fill_pieces.dart';

/// the-fill-ramp-is-cut-at-its-box-Q1 (유저 답 10-09: 「상자를 한 칸 넓혀
/// 어디서나 번지게」): a fill's anti-alias ramp spreads ONE PIXEL past its
/// edge on EVERY side — the box a fill is finished in holds that pixel
/// ([fillFinishReach]).
///
/// ↩️The box was the coverage grown by the expand alone, so a ramp that met
/// its edge was cut there: the shape tool's 4px horizontal plain line read
/// `86 · 100 · 100 · 86 · 14%`, the spread below it and not above, and the
/// bucket lost its spread at the last cells it filled.
void main() {
  // The ramp alone: no expand, so the box was the coverage itself.
  const ramp = FloodFillOptions(expandPx: 0, antiAlias: true);

  test('🚨an area\'s ramp spreads past it on every side — the shape tool\'s '
      'plain line reads the same at its top and its bottom, at its left and '
      'its right', () {
    // A 4px band: rows 10..13, columns 10..29.
    final pieces = buildRegionFillDabs(
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 10, top: 10, right: 30, bottom: 14),
      ),
      color: 0xFF000000,
      options: ramp,
    );
    final down = [for (var y = 8; y <= 15; y += 1) piecesAlphaAt(pieces, 20, y)];
    final across = [
      for (var x = 8; x <= 31; x += 1) piecesAlphaAt(pieces, x, 12),
    ];

    expect(down[1], greaterThan(0), reason: 'the row above the band');
    expect(down[6], greaterThan(0), reason: 'the row below the band');
    expect(down[1], down[6], reason: 'the same spread above and below');
    expect(down[2], down[5], reason: 'the same edge inside, top and bottom');
    expect([down.first, down.last], [0, 0], reason: 'one pixel, no more');

    expect(across[1], greaterThan(0), reason: 'the column left of the band');
    expect(across[22], greaterThan(0), reason: 'the column right of it');
    expect(across[1], across[22], reason: 'the same spread left and right');
    expect([across.first, across.last], [0, 0], reason: 'one pixel, no more');
  });

  test('🚨the bucket\'s ramp spreads past the last cells it filled, on every '
      'side — onto the outline it stopped at', () {
    // A white 16×16 raster with a black square outline (4,4)..(11,11):
    // the bucket fills its inside, (5..10, 5..10).
    const size = 16;
    final rgb = Uint8List(size * size * 4)..fillRange(0, size * size * 4, 255);
    for (var i = 4; i <= 11; i += 1) {
      for (final (x, y) in [(i, 4), (i, 11), (4, i), (11, i)]) {
        final at = (y * size + x) * 4;
        rgb
          ..[at] = 0
          ..[at + 1] = 0
          ..[at + 2] = 0;
      }
    }

    final region = floodFillRegion(
      rgb: rgb,
      width: size,
      height: size,
      seedX: 8,
      seedY: 8,
      options: ramp,
    )!;
    int at(int x, int y) {
      final lx = x - region.left;
      final ly = y - region.top;
      if (lx < 0 || ly < 0 || lx >= region.width || ly >= region.height) {
        return 0;
      }
      return region.mask[ly * region.width + lx];
    }

    final onTheOutline = [at(8, 4), at(8, 11), at(4, 8), at(11, 8)];
    expect(
      onTheOutline,
      everyElement(greaterThan(0)),
      reason: 'top, bottom, left and right: the ramp reaches the outline',
    );
    expect(onTheOutline.toSet(), hasLength(1), reason: 'the same on each');
    expect(
      [at(8, 3), at(8, 12), at(3, 8), at(12, 8)],
      everyElement(0),
      reason: 'one pixel past the fill, no more',
    );
  });

  test('what a finish reaches: the expand, and with the anti-alias one pixel '
      'more', () {
    expect(fillFinishReach(const FloodFillOptions(expandPx: 0)), 1);
    expect(
      fillFinishReach(const FloodFillOptions(expandPx: 3, antiAlias: false)),
      3,
    );
    expect(fillFinishReach(const FloodFillOptions(expandPx: 3)), 4);
  });
}
