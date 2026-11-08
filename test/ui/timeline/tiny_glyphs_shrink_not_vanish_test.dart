import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/text/word_bake.dart';

/// 🚨★★★TINY TEXT SHRINKS INTO A MARK. IT DOES NOT VANISH.
///
/// `timelineFittedGlyphFontSize` floors the fitted size at 4.0 so names
/// 「절대 안 사라지도록」 (R26 #38/#4) — and at deep zoom-out they went
/// anyway. 유저 2026-08-28: 「타임시트패널 줌아웃 하다보면 글자 사라지는데
/// 그거로 티나거든」.
///
/// 🧪THE CAUSE WAS MEASURED, not guessed (2026-08-29). Rasterising "12" at
/// 4px leaves mean alpha 136 across its box; rasterising at 12px and
/// box-filtering into the same box leaves 212. **Both peak at 255** — so
/// the ink was never missing. It was BLOTCHY: dark only where a stroke
/// landed on the pixel grid, and a blotch tinted with cell ink reads as
/// nothing.
///
/// ⛔SO THIS IS 「뭔가 적혀 있다」 AND NOT 「글자를 읽는다」. 유저 chose that
/// scope knowingly (A). Reading "12" at three pixels is not on offer from
/// any amount of filtering; that would be a wider cell or a different
/// mark.
///
/// ⛔AND ZOOM-IN MAY NOT MOVE. 유저 2026-08-28: 「줌인하면 텍스트는 선명하게
/// 보고싶다는게 래스터랑 다른점」. That is the assertion that matters most
/// here — a change that improved the tiny case by blurring the ordinary
/// one would have traded away the thing being protected.
void main() {
  test('the fitted size still floors at 4, and still shrinks below 14', () {
    // The floor is the reason a bake can be tiny at all. If it ever went
    // away the downscale would have nothing to do — and the text would be
    // gone for a different reason.
    expect(timelineFittedGlyphFontSize(12, 40), 12, reason: 'roomy cell');
    expect(timelineFittedGlyphFontSize(12, 10), closeTo(7.8, 0.01));
    expect(
      timelineFittedGlyphFontSize(12, 1),
      4,
      reason: 'the floor, and the size the downscale exists to rescue',
    );
  });

  test('the bake scale is 1 at and above the legible size', () {
    // ⛔THE ZOOM-IN GUARANTEE: the oversample only turns on BELOW the
    // legible size, and the ordinary path multiplies by exactly 1 — a
    // glyph the rasteriser already draws well is baked as it always was.
    expect(wordBakeScale(legibleBakeSize), 1);
    expect(wordBakeScale(14), 1);
    expect(wordBakeScale(legibleBakeSize / 2), 2);
    // ↩️The source was scanned here for an arm that handed the raster back
    // unfiltered at scale 1 (`times==wordBakedAsItIs?big`). There is no arm
    // now (2026-10-08): every bake goes through the average, and what keeps
    // 「no rounding on the path that was already right」 is that the average
    // of ONE pixel is that pixel — measured, not scanned, in the engine's
    // bake since 2026-11-08 (`kernels/letters/words/tests.rs`: a word
    // neither narrowed nor rastered over is its raster byte for byte, and a
    // thin stroke is averaged into its pixel, not dropped — the average's
    // other pins went there with it).
  });

  test('the shrink happens before the atlas, so the GLYPH op is untouched', () {
    // ⛔The native blit takes (destX, destY, atlasX, atlasY, width, height,
    // rgba) and no scale. Downscaling on the way IN keeps the ABI where it
    // is; a scaled blit would be a native change for a Dart-side problem.
    final ops = File(
      'lib/src/ui/timeline/timeline_grid_tile_ops.dart',
    ).readAsStringSync();
    final glyph = ops.substring(ops.indexOf('void glyph('));
    final signature = glyph.substring(0, glyph.indexOf(') {'));
    expect(
      signature.contains('scale'),
      isFalse,
      reason:
          'if a scale ever joins the op, this test should be revisited '
          'rather than silently left behind',
    );
  });
}
