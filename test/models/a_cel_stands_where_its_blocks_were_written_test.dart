import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cel_bank_lanes.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';

/// F-284 (유저 2026-10-04): 「링크된 오디오 링크버튼눌러서 쓰는곳 확인할때,
/// 인덱스도 표시 … S1의 15」 — a list that sends a person to a drawing says
/// where its blocks stand.
///
/// WHERE is the frames a person wrote its blocks on ([laneBlockStarts]),
/// through the filter that says whether a cel is exposed at all
/// ([laneExposesFrame]): the two cannot disagree about a ghost.
void main() {
  const a = FrameId('a');
  const b = FrameId('b');

  TimelineExposure block(FrameId id, int length) =>
      TimelineExposure.drawing(id, length: length);

  TimelineExposure ghost(FrameId id, TimelineRunEdgeMode mode) =>
      TimelineExposure.drawing(
        id,
        length: 1,
        ghostOf: TimelineRunEdgeGhost(
          side: TimelineRunEdgeSide.end,
          mode: mode,
        ),
      );

  SplayTreeMap<int, TimelineExposure> lane(
    Map<int, TimelineExposure> entries,
  ) => SplayTreeMap.of(entries);

  test('every cel by the frames its blocks start on, in the order of the '
      'row', () {
    expect(
      laneBlockStarts(lane({14: block(a, 2), 0: block(a, 4), 6: block(b, 1)})),
      {
        a: [0, 14],
        b: [6],
      },
    );
  });

  test('🚨a ghost is no place — a hold or a repeat projects it from the '
      'block that owns it', () {
    final held = lane({
      2: block(a, 2),
      4: ghost(a, TimelineRunEdgeMode.hold),
      8: ghost(b, TimelineRunEdgeMode.repeat),
    });
    expect(laneBlockStarts(held), {
      a: [2],
    });
    expect(laneExposesFrame(held, a), isTrue);
    expect(
      laneExposesFrame(held, b),
      isFalse,
      reason: 'one filter: a cel only ghosts show is exposed nowhere, and '
          'stands nowhere',
    );
  });

  test('an empty row places nothing', () {
    expect(laneBlockStarts(lane({})), isEmpty);
  });
}
