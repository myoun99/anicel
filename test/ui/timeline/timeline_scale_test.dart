import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_scale.dart';

void main() {
  test('leftForFrame maps frames to pixels', () {
    const scale = TimelineScale(pixelsPerFrame: 8, minBlockWidth: 96);

    expect(scale.leftForFrame(0), 0);
    expect(scale.leftForFrame(24), 192);
  });

  test('a block ends at its last frame\'s boundary, or its visual minimum '
      'on from its start', () {
    const scale = TimelineScale(pixelsPerFrame: 8, minBlockWidth: 96);

    expect(scale.blockEndFor(10, 12), 80 + 96);
    expect(scale.blockEndFor(10, 24), 80 + 192);
  });

  test('🚨F-220: widths are distances between boundaries — a span and its '
      'neighbours tile the axis at a zoom that is not whole pixels', () {
    const scale = TimelineScale(pixelsPerFrame: 7.3, minBlockWidth: 0);

    var right = 0.0;
    for (final (start, end) in [(0, 3), (3, 4), (4, 11)]) {
      expect(scale.leftForFrame(start), right, reason: 'no gap, no overlap');
      right = scale.leftForFrame(start) + scale.spanWidth(start, end);
      expect(right, right.roundToDouble(), reason: 'on a whole pixel');
    }
    expect(right, scale.leftForFrame(11));
  });

  test('frameAt reads leftForFrame back, and framesCovering counts the '
      'cells an extent reaches into', () {
    const scale = TimelineScale(pixelsPerFrame: 7.3);

    for (var frame = 0; frame < 40; frame += 1) {
      final left = scale.leftForFrame(frame);
      expect(scale.frameAt(left), frame, reason: 'on its own boundary');
      expect(
        scale.frameAt(scale.leftForFrame(frame + 1) - 0.01),
        frame,
        reason: 'up to the next boundary',
      );
      expect(scale.framesCovering(left), frame);
      expect(scale.framesCovering(left + 0.5), frame + 1);
    }
  });
}
