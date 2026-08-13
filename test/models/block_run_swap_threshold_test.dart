import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/block_run_move.dart';

/// 🚨F/T14 — **a run swaps when the cursor reaches the seat it will sit in
/// after the swap** (유저 확정 2026-08-14).
///
/// > 「**커서랑 판정이랑 일치**하도록. A가 10코마 끌어야하는거. 그게 직관적임
/// > … A10코마 B1코마의 경우 … **A를 1코마 끌면 A가 바뀌게 되는거니까**」
///
/// So the travel a swap costs is the NEIGHBOUR's length, and the block is
/// under the hand at the instant it moves. The retired rule compared
/// midpoints, which cost (mine + neighbour) ÷ 2 — 5.5 frames for a 1-frame
/// block to pass a 10-frame one, landing nowhere near the cursor.
///
/// ⚠️`block_run_move` is the ONE rule both axes use, so the storyboard's cut
/// drag changes with this. 유저 승인 완료 (「통일로직이니까」).
List<int> _orderAfter({
  required List<BlockMoveSlot> slots,
  required int runStart,
  required int runEnd,
  required int frameDelta,
}) => planBlockRunMove(
  slots: slots,
  runStart: runStart,
  runEnd: runEnd,
  frameDelta: frameDelta,
).order;

int _startOf({
  required List<BlockMoveSlot> slots,
  required int runStart,
  required int runEnd,
  required int frameDelta,
  required int slotIndex,
}) {
  final layout = planBlockRunMove(
    slots: slots,
    runStart: runStart,
    runEnd: runEnd,
    frameDelta: frameDelta,
  );
  return layout.starts[layout.order.indexOf(slotIndex)];
}

void main() {
  group('a short block passing a long one', () {
    // 유저 예시 1: A(1)@0 · B(10)@1. After the swap A sits at frame 10, so
    // that is the travel — 10, not the midpoint rule's 5.5.
    const slots = <BlockMoveSlot>[
      (leadingGap: 0, length: 1),
      (leadingGap: 0, length: 10),
    ];

    test('9 frames is not enough — the seat is at 10', () {
      expect(
        _orderAfter(slots: slots, runStart: 0, runEnd: 0, frameDelta: 9),
        [0, 1],
        reason: 'the cursor has not reached the seat A would land in',
      );
    });

    test('10 frames swaps, and A lands exactly under the cursor', () {
      expect(
        _orderAfter(slots: slots, runStart: 0, runEnd: 0, frameDelta: 10),
        [1, 0],
      );
      expect(
        _startOf(
          slots: slots,
          runStart: 0,
          runEnd: 0,
          frameDelta: 10,
          slotIndex: 0,
        ),
        10,
        reason: 'zero jump: the block is where the hand is',
      );
    });

    test('the retired midpoint rule would have swapped at 6', () {
      expect(
        _orderAfter(slots: slots, runStart: 0, runEnd: 0, frameDelta: 6),
        [0, 1],
        reason: '(1 + 10) ÷ 2 = 5.5 was the old threshold; it is gone',
      );
    });
  });

  group('a long block passing a short one', () {
    // 유저 예시 2: A(10)@0-9 · B(1)@10. After the swap A sits at frame 1, so
    // ONE frame of travel is the whole cost — the case that made the old
    // rule feel wrong in the other direction.
    const slots = <BlockMoveSlot>[
      (leadingGap: 0, length: 10),
      (leadingGap: 0, length: 1),
    ];

    test('one frame swaps', () {
      expect(
        _orderAfter(slots: slots, runStart: 0, runEnd: 0, frameDelta: 1),
        [1, 0],
      );
      expect(
        _startOf(
          slots: slots,
          runStart: 0,
          runEnd: 0,
          frameDelta: 1,
          slotIndex: 0,
        ),
        1,
      );
    });
  });

  group('the two directions cost the same', () {
    // The asymmetry the midpoint rule existed to avoid: passing a neighbour
    // must cost its length whichever way the hand goes.
    const slots = <BlockMoveSlot>[
      (leadingGap: 0, length: 10),
      (leadingGap: 0, length: 1),
    ];

    test('dragging the SHORT block left past the long one costs 10', () {
      // B is slot 1, sitting at frame 10. Its seat after the swap is 0.
      expect(
        _orderAfter(slots: slots, runStart: 1, runEnd: 1, frameDelta: -9),
        [0, 1],
        reason: 'nine frames leaves it one short of the seat',
      );
      expect(
        _orderAfter(slots: slots, runStart: 1, runEnd: 1, frameDelta: -10),
        [1, 0],
      );
    });
  });

  test('a leading gap belongs to the POSITION, so the seat includes it', () {
    // A row whose first block sits at frame 5, two frames long, with the
    // second glued to its end at frame 7. The seat the second block lands
    // in is frame 5 — the gap stays at the FRONT rather than travelling
    // with the block that arrived carrying it.
    //
    // So the travel is 2, the neighbour's length, exactly as it is on a row
    // with no gaps at all. A rule that measured from frame 0 would ask for
    // 7 here and the gap would silently make one row behave unlike another.
    const slots = <BlockMoveSlot>[
      (leadingGap: 5, length: 2),
      (leadingGap: 0, length: 3),
    ];
    expect(
      _orderAfter(slots: slots, runStart: 1, runEnd: 1, frameDelta: -1),
      [0, 1],
      reason: 'one frame leaves it short of the seat at 5',
    );
    expect(
      _orderAfter(slots: slots, runStart: 1, runEnd: 1, frameDelta: -2),
      [1, 0],
      reason: 'two — the neighbour is two long',
    );
    expect(
      _startOf(
        slots: slots,
        runStart: 1,
        runEnd: 1,
        frameDelta: -2,
        slotIndex: 1,
      ),
      5,
      reason: 'and it lands on the seat, not at frame 0',
    );
  });
}
