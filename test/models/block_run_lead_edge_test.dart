import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/block_run_lead_edge.dart';
import 'package:anicel/src/models/block_run_move.dart';

/// THE LEAD EDGE MOVES ONE BOUNDARY (I-21, 유저 2026-09-12 — 「프리미어
/// 프로처럼 … 앞 블록의 헤드 그대로 두고, 그 블록이랑 현재 블록이랑 코마를
/// 조절해서 전체적으론 안움직이도록」). Stated once here so the cut axis and
/// the frame axis give the same answer.
///
/// ↩️These cases REPLACED the old law wholesale, and that is the point: the
/// glued predecessor used to translate wholesale with its whole chain and
/// leave the difference at the head of the film. It now keeps its head and
/// changes its LENGTH, which is why nothing in front moves at all.
void main() {
  List<int> startsOf(BlockRunLeadEdgeLayout layout) {
    final starts = <int>[];
    var cursor = 0;
    for (var i = 0; i < layout.leadingGaps.length; i += 1) {
      cursor += layout.leadingGaps[i];
      starts.add(cursor);
      cursor += layout.lengths[i];
    }
    return starts;
  }

  List<BlockMoveSlot> slots(List<(int, int)> pairs) => [
    for (final pair in pairs) (leadingGap: pair.$1, length: pair.$2),
  ];

  test('a GLUED predecessor keeps its head and LENGTHENS by what the drag '
      'gave up — the pair trades across the boundary', () {
    // [0,4) [4,8) [8,12), all glued. Shrink the middle from the front by 2.
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 4), (0, 4)]),
      targetIndex: 1,
      frameDelta: 2,
    );

    expect(
      layout.lengths,
      [6, 2, 4],
      reason: 'the frames the target gave up went to the neighbour, not to '
          'the head of the film',
    );
    expect(
      startsOf(layout),
      [0, 6, 8],
      reason: 'both outer blocks stand exactly where they stood — the only '
          'thing that moved is the boundary the hand was holding',
    );
    expect(layout.leadingGaps, [0, 0, 0], reason: 'no emptiness appears');
  });

  test('the chain in FRONT does not move at all — heads are pinned', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 3), (0, 3), (0, 3), (0, 6)]),
      targetIndex: 3,
      frameDelta: 4,
    );

    expect(
      startsOf(layout),
      [0, 3, 6, 13],
      reason: 'only the dragged boundary moved; the first two blocks are '
          'not even adjacent to it',
    );
    expect(layout.lengths, [3, 3, 7, 2], reason: 'the neighbour absorbed 4');
  });

  test('a SEPARATED predecessor holds and the GAP absorbs the move', () {
    // [0,4) then a 3-frame gap then [7,11). Shrinking from the front with a
    // gap already between them feeds the gap, not the neighbour.
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (3, 4)]),
      targetIndex: 1,
      frameDelta: 2,
    );

    expect(startsOf(layout), [0, 9]);
    expect(layout.lengths, [4, 2], reason: 'nothing in front changed length');
    expect(layout.leadingGaps, [0, 5], reason: 'the gap simply grew');
  });

  test('growing forward spends the GAP first, then the neighbour\'s frames, '
      'and STOPS when the neighbour is down to one', () {
    // [0,4) then a 2-frame gap then [6,10): 2 frames of gap, and the
    // neighbour can give 3 more before it would fall under one frame.
    for (final asked in [-5, -999]) {
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (2, 4)]),
        targetIndex: 1,
        frameDelta: asked,
      );

      expect(
        layout.lengths,
        [1, 9],
        reason: 'asked for $asked: the gap paid 2 and the neighbour paid 3, '
            'which is everything it had above the floor',
      );
      expect(
        startsOf(layout),
        [0, 1],
        reason: 'the neighbour still starts where it started — it got '
            'SHORTER, it did not move',
      );
      expect(layout.leadingGaps, [0, 0], reason: 'the gap was spent');
    }
  });

  test('shrinking stops at the dragged block\'s own minimum', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 4)]),
      targetIndex: 1,
      frameDelta: 99,
      limits: (minLength: 2, reach: 1),
    );

    expect(layout.lengths, [6, 2]);
    expect(startsOf(layout), [0, 6], reason: 'the neighbour held its head');
  });

  test('the FIRST slot has no neighbour — the head of the axis absorbs it', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 6), (0, 4)]),
      targetIndex: 0,
      frameDelta: 2,
    );

    expect(layout.leadingGaps, [2, 0]);
    expect(layout.lengths, [4, 4]);
    expect(
      startsOf(layout),
      [2, 6],
      reason: 'the follower never moves: the end boundary held',
    );
  });

  test('the FIRST slot growing forward stops at frame 0', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(2, 4), (0, 4)]),
      targetIndex: 0,
      frameDelta: -99,
    );

    expect(layout.leadingGaps, [0, 0]);
    expect(layout.lengths, [6, 4], reason: 'it grew by the 2 frames of head');
  });

  test('a block ALREADY under the floor refuses to shrink instead of '
      'throwing — the clamp bounds cannot cross', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 2)]),
      targetIndex: 1,
      frameDelta: 3,
      limits: (minLength: 5, reach: 1),
    );

    expect(layout.lengths, [4, 2], reason: 'nothing shrinks below the floor');
    expect(startsOf(layout), [0, 4]);
  });

  group('reach — how far in front the edge may trade (유저 2026-09-12)', () {
    test('with reach 2 the squeeze WALKS: the nearest block goes to one '
        'frame, then the next, and the squeezed ones pack forward', () {
      // [0,4) [4,8) [8,12), all glued. Grow the last one's front by 5: the
      // neighbour gives 3 (4 → 1) and the one beyond it gives 2 (4 → 2).
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (0, 4), (0, 4)]),
        targetIndex: 2,
        frameDelta: -5,
        limits: (minLength: 1, reach: 2),
      );

      expect(layout.lengths, [2, 1, 9]);
      expect(
        startsOf(layout),
        [0, 2, 3],
        reason: 'the squeezed neighbour was PUSHED forward as the block in '
            'front of it gave up frames; the front-most head never moved',
      );
    });

    test('it stops at the HEAD of the last block it may reach', () {
      // Same run, asked for far more than exists: 3 + 3 = 6 frames are all
      // the two blocks in front can give before they hit one frame each.
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (0, 4), (0, 4)]),
        targetIndex: 2,
        frameDelta: -999,
        limits: (minLength: 1, reach: 2),
      );

      expect(layout.lengths, [1, 1, 10]);
      expect(
        startsOf(layout),
        [0, 1, 2],
        reason: 'both are down to one frame and packed against the head of '
            'the first — the drag can go no further',
      );
    });

    test('reach 1 is the default and still stops at the first neighbour', () {
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (0, 4), (0, 4)]),
        targetIndex: 2,
        frameDelta: -999,
      );

      expect(
        layout.lengths,
        [4, 1, 7],
        reason: 'the block beyond the neighbour was never asked',
      );
      expect(startsOf(layout), [0, 4, 5]);
    });

    test('gaps inside the reach are spent before the blocks are', () {
      // [0,2) gap(1) [3,5) gap(2) [7,9): growing the last by 4 spends the
      // 2-frame gap, then 2 frames of the block in front of it.
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 2), (1, 2), (2, 2)]),
        targetIndex: 2,
        frameDelta: -4,
        limits: (minLength: 1, reach: 2),
      );

      expect(layout.lengths, [2, 1, 6], reason: 'the gap paid 2, the block 1');
      expect(startsOf(layout), [0, 2, 3]);
    });
  });

  test('a zero delta changes nothing', () {
    final input = slots([(1, 4), (0, 4), (3, 4)]);
    final layout = planBlockRunLeadEdge(
      slots: input,
      targetIndex: 1,
      frameDelta: 0,
    );

    expect(layout.leadingGaps, [1, 0, 3]);
    expect(layout.lengths, [4, 4, 4]);
  });
}
