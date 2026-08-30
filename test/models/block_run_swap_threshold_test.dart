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

  test('a row\'s EMPTY HEAD belongs to neither block, so the seat is the '
      'neighbour\'s own start', () {
    // A row whose first block sits at frame 5, two frames long, with the
    // second glued to its end at frame 7. There is no slack BETWEEN them,
    // so the travel is 2 — the neighbour's length — exactly as it is on a
    // row with no gaps at all.
    //
    // ⛔The five frames in front are the row's head, not the first block's
    // fare. Charging them to the seat made this block travel 7 to swap with
    // a neighbour it was already touching, which is a row behaving unlike
    // an identical row that happens to start at 0.
    //
    // 🚨A gap BETWEEN two blocks is the other case and it IS charged: 유저
    // 확정 2026-08-30 (안 A) 「빈칸을 다 쓴 뒤에야 자리를 바꿉니다」. Both
    // fall out of one sentence — the run has passed a neighbour when its own
    // far edge has cleared that neighbour's far edge.
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

  test('🚨a gap BETWEEN two blocks is crossed BEFORE the swap, both ways', () {
    // 유저 확정 2026-08-30 (board `R4q-gap-belongs-to`, 안 A):
    //
    // > 「빈칸을 먼저 지난다 … 선택이 빈칸으로 들어가고 4 는 제자리.
    // > **빈칸을 다 쓴 뒤에야 4 와 자리를 바꿉니다**」
    //
    // ⚠️THIS IS THE CUT AXIS TOO. `planCutMove` hands its cuts to this same
    // function, and 유저 said so in the same breath: 「이런 드래그 블록
    // 로직은 다 **컷블록이랑 완전히 싹 다 전부다 통일**이니까」. Stating it
    // here rather than in the row's own test is what makes that true rather
    // than claimed.
    const rightward = <BlockMoveSlot>[
      (leadingGap: 0, length: 1),
      (leadingGap: 0, length: 2),
      (leadingGap: 1, length: 1),
    ];
    expect(
      _orderAfter(slots: rightward, runStart: 1, runEnd: 1, frameDelta: 1),
      [0, 1, 2],
      reason: 'one frame only spends the slack — the block past it stays put',
    );
    expect(
      _orderAfter(slots: rightward, runStart: 1, runEnd: 1, frameDelta: 2),
      [0, 2, 1],
      reason: 'the second frame is the neighbour, which is one long',
    );

    // The mirror, and it has to be measured rather than assumed: the two
    // directions are asked by different loops on purpose.
    const leftward = <BlockMoveSlot>[
      (leadingGap: 0, length: 1),
      (leadingGap: 0, length: 1),
      (leadingGap: 1, length: 2),
    ];
    expect(
      _orderAfter(slots: leftward, runStart: 2, runEnd: 2, frameDelta: -1),
      [0, 1, 2],
      reason: 'the run backs into the slack and nothing has been passed yet',
    );
    expect(
      _orderAfter(slots: leftward, runStart: 2, runEnd: 2, frameDelta: -2),
      [0, 2, 1],
      reason: 'slack plus the neighbour, the same total from the other end',
    );
  });
}
