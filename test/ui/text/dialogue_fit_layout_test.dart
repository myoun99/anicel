import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/dialogue_fit_layout.dart';

void main() {
  test('glyph centers distribute evenly across the extent', () {
    expect(dialogueGlyphCenters(glyphCount: 0, mainExtent: 100), isEmpty);
    expect(dialogueGlyphCenters(glyphCount: 1, mainExtent: 100), [50.0]);
    expect(dialogueGlyphCenters(glyphCount: 2, mainExtent: 100), [25.0, 75.0]);
    expect(dialogueGlyphCenters(glyphCount: 4, mainExtent: 120), [
      15.0,
      45.0,
      75.0,
      105.0,
    ]);
  });

  test('centers stay symmetric around the span midpoint', () {
    final centers = dialogueGlyphCenters(glyphCount: 5, mainExtent: 333);
    for (var i = 0; i < centers.length; i += 1) {
      expect(
        centers[i] + centers[centers.length - 1 - i],
        moreOrLessEquals(333),
      );
    }
  });

  test('each glyph owns an even cell, its centre in the middle', () {
    expect(dialogueGlyphCellExtent(glyphCount: 0, mainExtent: 100), 0);
    expect(dialogueGlyphCellExtent(glyphCount: 4, mainExtent: 120), 30);
  });

  test('🚨F-358: a window shows the glyphs whose centre it holds — the '
      'whole run\'s, not its own share spread again', () {
    // Centres 15, 45, 75, 105.
    expect(
      dialogueGlyphsShownIn(glyphCount: 4, mainExtent: 120),
      (first: 0, end: 4),
    );
    expect(
      dialogueGlyphsShownIn(glyphCount: 4, mainExtent: 120, from: 45),
      (first: 1, end: 4),
      reason: 'a centre on the opening edge is the window\'s',
    );
    expect(
      dialogueGlyphsShownIn(
        glyphCount: 4,
        mainExtent: 120,
        from: 46,
        to: 105,
      ),
      (first: 2, end: 3),
      reason: 'and one on the closing edge is the next window\'s',
    );
    expect(
      dialogueGlyphsShownIn(glyphCount: 0, mainExtent: 120, from: 10),
      (first: 0, end: 0),
    );
  });

  // F-93's narrowing moved to `word_condensation_test.dart` with the rule
  // itself — it is every block word's now, not the dialogue's alone.
}
