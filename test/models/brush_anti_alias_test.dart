// THE FOUR STEPS, AS NUMBERS.
//
// 유저 2026-09-08, after drawing Clip Studio's G펜 at all four settings:
// 「굵기 안바꾸고 가장자리만 조이는거였어」. ↩️I-50 (2026-09-30) split what a
// step means by tip: an analytic round tip is GIVEN an edge [edgeWidth] wide
// inside its rim, every other tip keeps the contrast ladder. Which one a dab
// takes, and what the ladder does to a coverage, is pinned with the law
// itself (`brush_edge_law_test.dart`); here are the numbers it reads.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_anti_alias.dart';

void main() {
  test('the ladder: 없음 cuts, and each step up loosens toward k = 1', () {
    expect(BrushAntiAlias.none.contrast, isNull);
    expect(BrushAntiAlias.low.contrast, 4.0);
    expect(BrushAntiAlias.medium.contrast, 2.0);
    expect(
      BrushAntiAlias.high.contrast,
      1.0,
      reason: '3단계 is the ramp a raster tip always had',
    );
  });

  test('the edge widths: 없음 gives none, and each step up is wider', () {
    expect(BrushAntiAlias.none.edgeWidth, 0.0);
    final widths = [
      for (final step in BrushAntiAlias.values) step.edgeWidth,
    ];
    for (var i = 1; i < widths.length; i += 1) {
      expect(
        widths[i],
        greaterThan(widths[i - 1]),
        reason: '${BrushAntiAlias.values[i]} must be softer than the step '
            'before it',
      );
    }
  });

  test('the index is Clip Studio\'s 0..3 order', () {
    // The importer is meant to map by index; this is the pin that says the
    // order is the one it will map through.
    expect(BrushAntiAlias.values.map((s) => s.index), [0, 1, 2, 3]);
    expect(BrushAntiAlias.none.index, 0);
    expect(BrushAntiAlias.high.index, 3);
  });

  test('named reads what toJson wrote, and shrugs at anything else', () {
    for (final step in BrushAntiAlias.values) {
      expect(BrushAntiAlias.named(step.toJson()), step);
    }
    expect(BrushAntiAlias.named(null), isNull);
    expect(BrushAntiAlias.named('sharp'), isNull);
  });
}
