import 'dart:io';
import 'dart:typed_data';

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
  /// Mean coverage across a bitmap — the number that decides whether a
  /// tinted glyph reads as a mark or as nothing.
  double mean(Uint8List a) =>
      a.isEmpty ? 0 : a.fold<int>(0, (s, v) => s + v) / a.length;

  test('the filter AVERAGES — it keeps ink a point sample would drop', () {
    // A one-pixel-wide stroke in an 8x8 field, shrunk to 2x2. Point
    // sampling lands between strokes and returns nothing; averaging keeps
    // the stroke's share. This IS the difference between "a mark is
    // there" and "the cell looks empty".
    final src = Uint8List(8 * 8);
    for (var y = 0; y < 8; y += 1) {
      src[y * 8 + 3] = 255; // one vertical stroke, column 3
    }
    final filtered = boxFilterA8(src, 8, 8, 2, 2);
    expect(filtered.length, 4);
    expect(
      mean(filtered),
      greaterThan(0),
      reason: 'the stroke survived the shrink',
    );
    // Column 3 of 8 falls in the LEFT destination column, so the left
    // half carries the ink and the right half is empty — the shape is
    // preserved, not smeared uniformly.
    expect(filtered[0], greaterThan(filtered[1]));
  });

  test('a full field stays full, and an empty one stays empty', () {
    // ⛔The two fixed points. A filter that dimmed a solid block would be
    // losing ink globally rather than redistributing it.
    final full = Uint8List(6 * 6)..fillRange(0, 36, 255);
    expect(boxFilterA8(full, 6, 6, 3, 3).every((v) => v == 255), isTrue);
    final empty = Uint8List(6 * 6);
    expect(
      boxFilterA8(empty, 6, 6, 3, 3).every((v) => v == 0),
      isTrue,
    );
  });

  test('every destination pixel is covered — no gaps at odd ratios', () {
    // 🚨A shrink whose source ranges skip a row leaves a dark band. 7→3 is
    // the awkward case: the ranges have to tile the source without holes.
    final src = Uint8List(7 * 7)..fillRange(0, 49, 200);
    final out = boxFilterA8(src, 7, 7, 3, 3);
    expect(out.length, 9);
    expect(
      out.every((v) => v == 200),
      isTrue,
      reason: 'a uniform field shrinks to a uniform field at any ratio',
    );
  });

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
    // of ONE pixel is that pixel — measured, not scanned. (That the bake of
    // such a word IS the word drawn straight, byte for byte:
    // `text/a_baked_word_stands_where_the_word_does_test.dart`.)
    final raster = Uint8List.fromList([
      for (var i = 0; i < 5 * 4; i += 1) (i * 37 + 11) % 256,
    ]);
    expect(
      boxFilterA8(raster, 5, 4, 5, 4),
      raster,
      reason: 'a raster averaged into a box its own size is itself',
    );
  });

  test('a pixel takes the PART of a source pixel it covers — a ratio that '
      'is no whole number shares no pixel between two windows', () {
    // 3 → 2: each pixel covers one and a half — a whole pixel and half the
    // middle one. ↩️The filter took every pixel a window touched, whole, so
    // the middle one counted in full on both sides: [75, 45].
    expect(boxFilterA8(Uint8List.fromList([90, 60, 30]), 3, 1, 2, 1), [80, 40]);
    // And down the other axis, by the same rule.
    expect(boxFilterA8(Uint8List.fromList([90, 60, 30]), 1, 3, 1, 2), [80, 40]);
    // Both at once: a pixel's mean weighs each source pixel by the AREA of
    // it that is covered — the corner one by a quarter.
    expect(
      boxFilterA8(
        Uint8List.fromList([90, 60, 30, 60, 60, 60, 30, 60, 240]),
        3,
        3,
        2,
        2,
      ),
      // (90 + 60/2 + 60/2 + 60/4) / 2.25 = 73.3 …, and so on round.
      [73, 46, 46, 140],
    );
  });

  test('a pixel told what it covers takes that — and what lies past the '
      'source\'s edge is empty, not left out of the mean', () {
    // Two source pixels each, starting one pixel before the source.
    expect(
      boxFilterA8(
        Uint8List.fromList([80, 40]),
        2,
        1,
        2,
        1,
        along: (origin: -1, step: 2),
      ),
      [40, 20],
    );
    // Half a pixel on: each row is half of two, and the last half is past
    // the end.
    expect(
      boxFilterA8(
        Uint8List.fromList([100, 50]),
        1,
        2,
        1,
        2,
        down: (origin: 0.5, step: 1),
      ),
      [75, 25],
    );
    // A row's end is the source's edge too: the pixel after it in memory is
    // the next row's first, and no pixel reads it (the last two bytes are a
    // row past the source, there so that a read too far has something to
    // read).
    expect(
      boxFilterA8(
        Uint8List.fromList([80, 40, 200, 100, 9, 9]),
        2,
        2,
        2,
        2,
        along: (origin: -1, step: 2),
      ),
      [40, 20, 100, 50],
    );
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
