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

  test('pulled into its floor, the dragged block holds there until the '
      'edge has passed it whole — then it is gone (I-179)', () {
    List<int> pulled(int pull) => planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 4)]),
      targetIndex: 1,
      frameDelta: pull,
      limits: (minLength: 2, reach: 1),
    ).lengths;

    expect(pulled(2), [6, 2], reason: 'down to its floor');
    expect(pulled(3), [6, 2], reason: 'the edge holds at the floor');
    expect(pulled(4), [8, 0], reason: 'passed whole, it is gone');
    expect(pulled(99), [8, 0], reason: 'as far as the row\'s last frame');
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

  test('a block ALREADY under the floor holds still instead of throwing — '
      'until the edge has passed it whole', () {
    BlockRunLeadEdgeLayout pulled(int pull) => planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 2)]),
      targetIndex: 1,
      frameDelta: pull,
      limits: (minLength: 5, reach: 1),
    );

    expect(pulled(1).lengths, [4, 2], reason: 'nothing shrinks below it');
    expect(startsOf(pulled(1)), [0, 4]);
    expect(pulled(2).lengths, [6, 0], reason: 'passed whole, it is gone');
  });

  group('pulled back past its last frame, the edge sweeps on (I-179, 유저 '
      '2026-11-19: 「자기 자신 없애고 뒤의 블록들도 없앨수있게」)', () {
    test('the block goes, then each one behind it, and the glued '
        'predecessor follows the edge', () {
      // [0,4) [4,5) [5,6) [6,7), all glued.
      List<int> pulled(int pull) => planBlockRunLeadEdge(
        slots: slots([(0, 4), (0, 1), (0, 1), (0, 1)]),
        targetIndex: 1,
        frameDelta: pull,
      ).lengths;

      expect(pulled(1), [5, 0, 1, 1], reason: '「자기 자신 없애고」');
      expect(pulled(2), [6, 0, 0, 1], reason: '「당길때마다 뒤에 것을 없앰」');
      expect(pulled(3), [7, 0, 0, 0]);
      expect(pulled(99), [7, 0, 0, 0], reason: 'the row ends where it ended');
    });

    test('a block the edge stands in is shortened from its front, its end '
        'where it was', () {
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (0, 2), (0, 5)]),
        targetIndex: 1,
        frameDelta: 4,
      );

      expect(layout.lengths, [8, 0, 3]);
      expect(startsOf(layout), [0, 8, 8]);
      expect(layout.leadingGaps, [0, 0, 0], reason: 'no emptiness appears');
    });

    test('a SEPARATED predecessor holds and the gap grows', () {
      // [0,4) .. [6,8) [8,11)
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (2, 2), (0, 3)]),
        targetIndex: 1,
        frameDelta: 4,
      );

      expect(layout.lengths, [4, 0, 1]);
      expect(startsOf(layout)[2], 10, reason: 'the follower ends at 11');
      expect(layout.leadingGaps, [0, 6, 0]);
    });

    test('through a gap behind it the glued predecessor goes on following, '
        'and a block past the edge holds still', () {
      // [0,4) [4,6) .. [9,11)
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (0, 2), (3, 2)]),
        targetIndex: 1,
        frameDelta: 3,
      );

      expect(layout.lengths, [7, 0, 2]);
      expect(startsOf(layout), [0, 7, 9]);
    });

    test('the FIRST block has no predecessor — the head of the axis grows', () {
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 1), (0, 1), (0, 1)]),
        targetIndex: 0,
        frameDelta: 2,
      );

      expect(layout.lengths, [0, 0, 1]);
      expect(startsOf(layout)[2], 2, reason: 'the last block holds still');
    });
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

  group('a band\'s lead edge pulled back thins it out (I-179-Q1, 유저 '
      '2026-11-19: 「솎아내기 — 당긴 칸 수만큼 건너뛰며 남긴다」)', () {
    /// The row as the user wrote it: each block by its number on the frame
    /// it starts, `-` on the frames it holds after that, `.` where none.
    String written(BlockRunLeadEdgeLayout layout) {
      final row = StringBuffer();
      final starts = startsOf(layout);
      for (var i = 0; i < starts.length; i += 1) {
        if (layout.lengths[i] > 0) {
          row
            ..write('.' * (starts[i] - row.length))
            ..write('${i + 1}${'-' * (layout.lengths[i] - 1)}');
        }
      }
      return row.toString();
    }

    String thinned(
      List<(int, int)> pairs, {
      required List<int> selected,
      required int pull,
    }) => written(
      planBlockRunThinning(
        slots: slots(pairs),
        selected: selected,
        pull: pull,
      ),
    );

    const onOnes = [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)];
    final eight = [...onOnes, (0, 1)];
    final all = [for (var i = 0; i < 8; i += 1) i];

    test('🗣️the user\'s eight on ones: one frame keeps every second, two '
        'every third — 「1-3-5-7-」 · 「1--4--7-」', () {
      expect(thinned(eight, selected: all, pull: 0), '12345678');
      expect(thinned(eight, selected: all, pull: 1), '1-3-5-7-');
      expect(thinned(eight, selected: all, pull: 2), '1--4--7-');
      expect(thinned(eight, selected: all, pull: 3), '1---5---');
    });

    test('pulled as far as the band holds blocks, the first is all that '
        'stays, the band\'s length whole — and no further', () {
      expect(thinned(eight, selected: all, pull: 7), '1-------');
      expect(thinned(eight, selected: all, pull: 99), '1-------');
    });

    test('counted in blocks, whatever their lengths', () {
      expect(
        thinned(
          [(0, 2), (0, 2), (0, 2), (0, 2)],
          selected: [0, 1, 2, 3],
          pull: 1,
        ),
        '1---3---',
      );
      expect(
        thinned(
          [(0, 1), (0, 3), (0, 2), (0, 1)],
          selected: [0, 1, 2, 3],
          pull: 1,
        ),
        '1---3--',
      );
    });

    test('nothing outside the band moves', () {
      final six = onOnes.take(6).toList();
      expect(thinned(six, selected: [1, 2, 3, 4], pull: 1), '12-4-6');
      expect(thinned(six, selected: [1, 2, 3, 4], pull: 3), '12---6');
      expect(thinned(six, selected: [1, 2, 3, 4], pull: 9), '12---6');
    });

    test('the last run short of a whole one is thinned as far as it goes',
        () {
      expect(
        thinned(onOnes.take(5).toList(), selected: [0, 1, 2, 3, 4], pull: 2),
        '1--4-',
      );
    });

    test('a band holding one block on a row keeps it', () {
      expect(thinned(eight, selected: [3], pull: 2), '12345678');
    });

    test('a gap is the single lead edge\'s: the block in front of it holds '
        'and the gap grows; one the edge passes through, the glued block '
        'in front follows over', () {
      const band = [0, 1, 2, 3];
      expect(
        thinned([(0, 1), (1, 1), (0, 1), (0, 1)], selected: band, pull: 1),
        '1..3-',
      );
      expect(
        thinned([(0, 1), (0, 1), (1, 1), (0, 1)], selected: band, pull: 2),
        '1---4',
      );
    });

    test('each run is swept as the lead edge of its second block pulled to '
        'the run\'s end would sweep it — the same rule, not a second one', () {
      final row = slots([(0, 2), (0, 1), (1, 3), (0, 1), (2, 2)]);
      final single = planBlockRunLeadEdge(
        slots: row,
        targetIndex: 1,
        // From block 2's start (2) to block 4's end (8).
        frameDelta: 6,
      );
      final band = planBlockRunThinning(
        slots: row,
        selected: [0, 1, 2, 3],
        pull: 3,
      );
      expect(written(band), written(single));
      expect(band.lengths, single.lengths);
      expect(band.leadingGaps, single.leadingGaps);
      expect(written(band), '1-------..5-');
    });
  });
}
