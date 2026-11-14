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
/// bucket lost its spread at the last cells it filled. (The bucket's ramp is
/// the engine kernel's: `the_fill_s_ramp_spreads_a_pixel_past_its_outline`,
/// `kernels/flood/tests.rs`.)
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
