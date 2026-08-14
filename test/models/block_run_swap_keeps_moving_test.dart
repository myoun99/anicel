import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/block_run_move.dart';

/// 🚨UI 피드백 08-14 #5 — **a swap does not end the drag.** The hand keeps
/// its hold on the run after the sequence flips, so the run goes on being
/// clamped into the free space of the rank it just took.
///
/// > 「프레임블록의 **앞뒤바꿈등 이동 로직이 이상함** … 그 **앞뒤 바꾸는
/// > 위치의 기준이 처음 드래그를 시작한곳**임 … 그리고 **앞뒤 넘어가고나서도
/// > 빈 프레임쪽 이동가능해야하는데 이동불가함**」
///
/// The user's two sentences are one bug seen twice. The reorder branch used
/// to drop `wanted` and seat the run, so ①the empty frames past the
/// neighbour were unreachable and ②from there on only the cursor moved,
/// which is what "measured from where I started dragging" looks like.
///
/// ⛔The neighbour is NOT pinned while this happens: a swap TRADES seats,
/// the neighbour pulling into the space the run vacated. Holding it still
/// instead is what broke three confirmed tests on 2026-08-14 — with the
/// neighbour pinned, a 1-frame block can never reach the seat under the
/// cursor because its 10-frame neighbour is still standing there.
///
/// ⚠️`block_run_move` is the ONE rule both axes use.
BlockRunMoveLayout _move({
  required List<BlockMoveSlot> slots,
  required int runStart,
  required int runEnd,
  required int frameDelta,
  int? axisEndExclusive,
}) => planBlockRunMove(
  slots: slots,
  runStart: runStart,
  runEnd: runEnd,
  frameDelta: frameDelta,
  axisEndExclusive: axisEndExclusive,
);

void main() {
  group('the empty frames past the neighbour are reachable', () {
    // A(1)@0, then twenty empty frames, then B(10)@21. The seat A swaps
    // into is frame 30 — B's length behind B's old head, gap included.
    const slots = <BlockMoveSlot>[
      (leadingGap: 0, length: 1),
      (leadingGap: 20, length: 10),
    ];

    test('the swap itself still lands exactly on the seat', () {
      final layout = _move(slots: slots, runStart: 0, runEnd: 0, frameDelta: 30);
      expect(layout.order, [1, 0]);
      expect(layout.startOf(0), 30, reason: 'the block is where the hand is');
    });

    test('one frame further keeps going — the old rule stopped dead here', () {
      final layout = _move(slots: slots, runStart: 0, runEnd: 0, frameDelta: 31);
      expect(layout.order, [1, 0]);
      expect(
        layout.startOf(0),
        31,
        reason: 'a seated run used to ignore the rest of the drag',
      );
    });

    test('and it keeps following the hand out into the empty space', () {
      final layout = _move(slots: slots, runStart: 0, runEnd: 0, frameDelta: 50);
      expect(layout.startOf(0), 50);
    });

    test('the neighbour pulls into the space the run left, not pinned', () {
      final layout = _move(slots: slots, runStart: 0, runEnd: 0, frameDelta: 31);
      expect(
        layout.startOf(1),
        0,
        reason: 'a swap trades seats: B takes the gap of the position it '
            'moved into, which is the head of the row',
      );
    });
  });

  group('leftward reads the same way', () {
    // Five empty, B(10)@5-14, A(1)@15. The seat A swaps into is frame 5 —
    // the head position's own leading gap, which stays at the front.
    const slots = <BlockMoveSlot>[
      (leadingGap: 5, length: 10),
      (leadingGap: 0, length: 1),
    ];

    test('the swap lands on the seat, gap included', () {
      final layout = _move(
        slots: slots,
        runStart: 1,
        runEnd: 1,
        frameDelta: -10,
      );
      expect(layout.order, [1, 0]);
      expect(layout.startOf(1), 5);
    });

    test('and then the empty head is reachable — the #5 complaint', () {
      final layout = _move(
        slots: slots,
        runStart: 1,
        runEnd: 1,
        frameDelta: -13,
      );
      expect(layout.order, [1, 0]);
      expect(layout.startOf(1), 2);
      expect(
        layout.startOf(0),
        6,
        reason: 'the follower absorbs the difference, as it does on a slide',
      );
    });

    test('past the head the run stops at frame 0', () {
      final layout = _move(
        slots: slots,
        runStart: 1,
        runEnd: 1,
        frameDelta: -20,
      );
      expect(layout.startOf(1), 0, reason: 'frame 0 is the floor');
    });
  });

  test('everything past the run still holds still', () {
    // Three blocks: the run swaps with its neighbour and slides inside the
    // new slack; the block beyond the pair must not notice.
    const slots = <BlockMoveSlot>[
      (leadingGap: 0, length: 2), // X @0..1
      (leadingGap: 3, length: 1), // Y @5
      (leadingGap: 4, length: 2), // Z @10..11
    ];
    // X's seat past Y is frame 4; one frame further is inside the slack.
    final layout = _move(slots: slots, runStart: 0, runEnd: 0, frameDelta: 5);

    expect(layout.order, [1, 0, 2], reason: 'X passed Y');
    expect(layout.startOf(0), 5);
    expect(layout.startOf(1), 0, reason: 'Y pulled into the head X vacated');
    expect(layout.startOf(2), 10, reason: 'Z never moved');
  });

  test('the judgement is still read off the ORIGINAL layout', () {
    // Coming back inside the neighbour's seat undoes the swap: the rank is
    // measured against where the blocks started, so the drag is reversible
    // within itself rather than chasing its own preview.
    const slots = <BlockMoveSlot>[
      (leadingGap: 0, length: 1),
      (leadingGap: 20, length: 10),
    ];
    expect(
      _move(slots: slots, runStart: 0, runEnd: 0, frameDelta: 29).order,
      [0, 1],
      reason: 'one short of the seat at 30',
    );
    expect(
      _move(slots: slots, runStart: 0, runEnd: 0, frameDelta: 29).startOf(0),
      20,
      reason: 'and it clamps at contact with B, which has not moved',
    );
  });

  test('an axis with an end still stops the run after a swap', () {
    // The storyboard's row lives inside its cut. A swap may not smuggle the
    // run past the end the axis declares.
    const slots = <BlockMoveSlot>[
      (leadingGap: 0, length: 2),
      (leadingGap: 1, length: 2),
    ];
    final layout = _move(
      slots: slots,
      runStart: 0,
      runEnd: 0,
      frameDelta: 40,
      axisEndExclusive: 8,
    );
    expect(layout.order, [1, 0]);
    expect(layout.startOf(0), 6, reason: '8 minus the run\'s own length');
  });
}
