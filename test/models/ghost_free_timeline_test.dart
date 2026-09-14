// A MOVE PLANS ON THE GHOST-FREE TIMELINE: DERIVED ENTRIES NEITHER MOVE NOR
// BLOCK.
//
// Both block-move planners kept their own copy of this filter until
// 2026-09-03; the mutation campaign turned one copy's `&&` into `||` (every
// drawing was dropped, not just the ghosts) and nothing noticed. One
// function now, and these pins say what it keeps. The round-8 audit
// (2026-09-06) found the multi-row planner, the run-edge insert and the
// rederive pass each still holding a copy; the one function lives with the
// ghost's constructor in timeline_repeat.dart and all four read it.
import 'package:flutter_test/flutter_test.dart';
import '../helpers/run_edge_fixtures.dart';

import 'package:anicel/src/models/timeline_repeat.dart';
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
        2: const TimelineExposure.drawing(
          FrameId('a'),
          length: 2,
          ghostOf: endHoldGhost,
        ),
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
