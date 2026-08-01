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

  test('HALF of any viewport is neutral middle, however small', () {
    // R10 R6 made small viewports reachable: the x-sheet's frame rail is
    // 66–96px at real dock heights. A fixed 24px band there is most of the
    // rail, and the rail scrubs from `onPointerDown` — so a plain press
    // inside the band scrolled the sheet and the playhead ran away under a
    // stationary pen. The band narrows instead.
    for (final extent in [
      1.0, 8.0, 16.0, 40.0, 48.0, 66.0, 96.0, 200.0, 1000.0,
    ]) {
      for (final t in [0.25, 0.4, 0.5, 0.6, 0.75]) {
        expect(
          edgeAutoPanDelta(extent * t, extent),
          0,
          reason: 'the middle of a $extent viewport must not pan (at $t)',
        );
      }
      // Both ends still push, so a real edge drag keeps working.
      expect(edgeAutoPanDelta(extent, extent), greaterThan(0));
      expect(edgeAutoPanDelta(0, extent), lessThan(0));
    }
  });

  test('a degenerate viewport pans nothing', () {
    expect(edgeAutoPanDelta(0, 0), 0);
    expect(edgeAutoPanDelta(10, -5), 0);
  });
}
