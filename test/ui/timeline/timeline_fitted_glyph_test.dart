import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';

/// #15: the fitted glyph size takes BOTH axes ("빡빡한 쪽으로" — whichever
/// is tighter wins, floor 4.0 kept), and differently-inked glyph rasters
/// never share a cache slot.
void main() {
  group('timelineFittedGlyphFontSize', () {
    test('wide cells keep the base size — the pre-#15 behaviour', () {
      expect(timelineFittedGlyphFontSize(12, 20), 12);
      expect(timelineFittedGlyphFontSize(9, 14), 9);
    });

    test('a narrow cell shrinks the type down to the 4.0 floor', () {
      expect(timelineFittedGlyphFontSize(12, 10), closeTo(7.8, 0.001));
      expect(timelineFittedGlyphFontSize(12, 1), 4.0);
    });

    test('the CROSS extent binds when it is the tighter axis (#15\'s '
        'vertical half); a roomy one changes nothing', () {
      expect(
        timelineFittedGlyphFontSize(12, 20, crossExtent: 10),
        closeTo(7.8, 0.001),
        reason: 'height 10 is the tight axis',
      );
      expect(
        timelineFittedGlyphFontSize(12, 20, crossExtent: 40),
        12,
        reason: 'both axes roomy',
      );
      expect(
        timelineFittedGlyphFontSize(12, 8, crossExtent: 10),
        closeTo(8 * 0.78, 0.001),
        reason: 'the main axis is still the tighter of the two',
      );
      expect(
        timelineFittedGlyphFontSize(12, 1, crossExtent: 1),
        4.0,
        reason: 'the floor holds on both axes',
      );
    });
  });

  group('ground-law glyphs', () {
    test('the resolved COLOR keys the cache: the black and white variants '
        'of one string never serve each other\'s raster', () {
      const style = TextStyle(fontSize: 11, color: Color(0xFF26282B));
      final plain = timelineGlyphPainter('24', style);
      final black = timelineGlyphPainter(
        '24',
        style.copyWith(color: timelineTextOnLightGroundColor),
      );
      final white = timelineGlyphPainter(
        '24',
        style.copyWith(color: timelineTextOnDarkGroundColor),
      );
      final whiteAgain = timelineGlyphPainter(
        '24',
        style.copyWith(color: timelineTextOnDarkGroundColor),
      );

      expect(identical(plain, black), isFalse);
      expect(identical(black, white), isFalse);
      expect(identical(white, whiteAgain), isTrue, reason: 'cached');
      expect(
        identical(plain, timelineGlyphPainter('24', style)),
        isTrue,
        reason: 'the plain entry survives alongside',
      );
    });
  });
}
