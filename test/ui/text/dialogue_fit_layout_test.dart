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
}
