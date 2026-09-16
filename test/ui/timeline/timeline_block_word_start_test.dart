import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';

/// F-96: where a word in a block starts along the frame axis — the one law
/// the name, the length, the tile bake and the storyboard's comma ask.
void main() {
  double start(
    double wordExtent,
    TimelineBlockWordGrowth growth, {
    double cellStart = 100,
    double cellExtent = 24,
  }) => timelineBlockWordStart(
    cellStart: cellStart,
    cellExtent: cellExtent,
    wordExtent: wordExtent,
    growth: growth,
  );

  test('a word that fits sits centred on its cell, whichever way it would '
      'grow', () {
    for (final growth in TimelineBlockWordGrowth.values) {
      expect(start(10, growth), 107, reason: '$growth');
    }
  });

  test('a name that outgrows its cell starts at the cell and grows toward '
      'the block end', () {
    expect(start(60, TimelineBlockWordGrowth.towardBlockEnd), 100);
  });

  test('a length that outgrows its cell ends at the cell and grows toward '
      'the block start', () {
    const width = 60.0;
    expect(
      start(width, TimelineBlockWordGrowth.towardBlockStart) + width,
      124,
    );
  });

  test('the edge takes over exactly where the word meets it — a word one '
      'pixel longer does not jump', () {
    for (final growth in TimelineBlockWordGrowth.values) {
      final atEdge = start(24, growth);
      expect(atEdge, 100, reason: '$growth: centred IS the edge at 24');
      expect(
        (start(24.5, growth) - atEdge).abs(),
        lessThanOrEqualTo(0.5),
        reason: '$growth',
      );
    }
  });
}
