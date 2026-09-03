// THE FILL'S DEFAULT KNOBS — what the Tool Settings panel starts from.
//
// The mutation campaign (2026-09-03) flipped the anti-alias default to false
// and nothing noticed: no test asked what a fresh FloodFillOptions holds.
// This pin does, for every knob at once.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/canvas_flood_fill.dart';

void main() {
  test('a fresh FloodFillOptions holds the panel defaults', () {
    const options = FloodFillOptions();
    expect(options.tolerance, 32);
    expect(options.expandPx, 1);
    expect(options.antiAlias, isTrue);
    expect(options.gapClosePx, 0);
    expect(options.extendBeyondCanvas, isFalse);
  });
}
