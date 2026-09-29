import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_scale.dart';

void main() {
  test('leftForFrame maps frames to pixels', () {
    const scale = TimelineScale(pixelsPerFrame: 8, minBlockWidth: 96);

    expect(scale.leftForFrame(0), 0);
    expect(scale.leftForFrame(24), 192);
  });

  test('a block ends at its end, or its minimum on from its start', () {
    const scale = TimelineScale(pixelsPerFrame: 8, minBlockWidth: 96);

    expect(scale.blockEndFor(10, 12), 80 + 96);
    expect(scale.blockEndFor(10, 24), 80 + 192);
  });
}
