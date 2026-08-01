import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 24px edge band every timeline and storyboard scrub shares.
void main() {
  test('the middle of a roomy viewport pans nothing', () {
    expect(edgeAutoPanDelta(100, 300), 0);
    expect(edgeAutoPanDelta(24, 300), 0);
    expect(edgeAutoPanDelta(276, 300), 0);
  });

  test('past either end, the delta is how far past', () {
    expect(edgeAutoPanDelta(290, 300), 14);
    expect(edgeAutoPanDelta(10, 300), -14);
  });

  test('a viewport shorter than BOTH bands pans nothing at all', () {
    // R10 R6 made this reachable for the first time: the x-sheet's frame
    // rail can be 16px tall in a short panel, and with the bands
    // overlapping every pointer position read as an edge push — a plain
    // press scrolled 32px and five sub-pixel moves ran the playhead
    // through five frames under a stationary pen.
    for (final extent in [0.0, 1.0, 16.0, 40.0, 47.9]) {
      for (final pos in [0.0, extent / 2, extent]) {
        expect(
          edgeAutoPanDelta(pos, extent),
          0,
          reason: 'pos $pos in a $extent viewport must not pan',
        );
      }
    }
  });

  test('the guard lets go exactly where the bands stop overlapping', () {
    // 48 is the first extent with a middle; a centre press there is still
    // quiet, and only a real edge push moves.
    expect(edgeAutoPanDelta(24, 48), 0);
    expect(edgeAutoPanDelta(30, 48), 6);
    expect(edgeAutoPanDelta(47.9, 47.8), 0);
  });
}
