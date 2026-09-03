// A MOVE PLANS ON THE GHOST-FREE TIMELINE: DERIVED ENTRIES NEITHER MOVE NOR
// BLOCK.
//
// Both block-move planners kept their own copy of this filter until
// 2026-09-03; the mutation campaign turned one copy's `&&` into `||` (every
// drawing was dropped, not just the ghosts) and nothing noticed. One
// function now, and these pins say what it keeps.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/drawing_block_move.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

void main() {
  test('authored drawings stay, ghost drawings go', () {
    final layer = Layer(
      id: const LayerId('l'),
      name: 'L',
      frames: const [],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('a'), length: 2),
        2: const TimelineExposure.drawing(FrameId('a'), length: 2, ghost: true),
        4: const TimelineExposure.drawing(FrameId('b'), length: 1),
      },
    );
    final base = ghostFreeTimeline(layer);
    expect(base.keys, [0, 4]);
    expect(base[0]!.frameId, const FrameId('a'));
    expect(base[4]!.frameId, const FrameId('b'));
  });

  test('an empty timeline stays empty', () {
    final layer = Layer(id: const LayerId('l'), name: 'L', frames: const []);
    expect(ghostFreeTimeline(layer), isEmpty);
  });
}
