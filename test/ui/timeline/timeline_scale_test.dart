import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_scale.dart';

void main() {
  test('leftForFrame maps frames to pixels', () {
    const scale = TimelineScale(pixelsPerFrame: 8, minBlockWidth: 96);

    expect(scale.leftForFrame(0), 0);
    expect(scale.leftForFrame(24), 192);
  });

  test('widthForDuration maps duration to pixels with visual minimum', () {
    const scale = TimelineScale(pixelsPerFrame: 8, minBlockWidth: 96);

    expect(scale.widthForDuration(12), 96);
    expect(scale.widthForDuration(24), 192);
  });
}
