import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/block_run_move.dart';

/// 🚨H9/H10 (유저 2026-08-22, 스크린샷 3장) — **THE ROW THE USER
/// PHOTOGRAPHED.** Five blocks; one is dragged across the others; the four
/// it passes froze wherever the permutation left them.
///
/// > 「여기서 하고싶은건 **원래 공간으로 회귀하려하는 시스템**을 넣고싶음.
/// > 지금 1,2,3,4가 **바뀐위치에 그냥 고정**되있는데, 그게아니라 **원래
/// > 위치가 비어있다면 거기로 최대한 회귀**하는거」
///
/// > 「**집으로 향하는 길이 비어있으면 최대한 그 길 향해서 이동**하도록
/// > 하는게 목표야. **집이 비어있으면 집으로이동 / 아니면 지금처럼
/// > 원래자리 고정이 아니야**」
///
/// ⛔The second sentence rules out reading the first as two branches. There
/// is no "home was taken, so something else decides" — a block always walks
/// toward the frame it started on and stops where the road stops.
///
/// ⚠️`block_run_move` is the ONE rule both axes use, so this is the frame
/// row AND the storyboard's cuts. See `cut_move_plan_test` for the same
/// sentence read on the cut axis.
void main() {
  // 1@0..1, 2@4..5, 3@8..9, 4@12..13, 5@16..17 — the photographed row.
  const row = <BlockMoveSlot>[
    (leadingGap: 0, length: 2),
    (leadingGap: 2, length: 2),
    (leadingGap: 2, length: 2),
    (leadingGap: 2, length: 2),
    (leadingGap: 2, length: 2),
  ];

  BlockRunMoveLayout dragLastBlock(int frameDelta) => planBlockRunMove(
    slots: row,
    runStart: 4,
    runEnd: 4,
    frameDelta: frameDelta,
  );

  test('the four blocks it passes are all still at home', () {
    // 5 dragged back to frame 6 — past 4 and 3, and stopped by 2's end.
    final layout = dragLastBlock(-10);

    expect(layout.order, [0, 1, 4, 2, 3], reason: '5 now sits between 2 and 3');
    expect(layout.startOf(4), 6, reason: 'the block is under the hand');
    expect(
      [for (var block = 0; block < 4; block += 1) layout.startOf(block)],
      [0, 4, 8, 12],
      reason: '「1,2,3,4가 바뀐위치에 그냥 고정」 is exactly what must NOT '
          'happen: nobody took their frames, so nobody left them',
    );
  });

  test('and the one it stands on gives up only the frames it is standing on', () {
    // One block further back: 5 lands ON 2's own start.
    final layout = dragLastBlock(-12);

    expect(layout.order, [0, 4, 1, 2, 3]);
    expect(layout.startOf(4), 4, reason: 'the block is under the hand');
    expect(
      layout.startOf(1),
      6,
      reason: '「최대한 그 길 향해서 이동」 — 2 is pushed off 4 and stops the '
          'first frame it can, not at the far seat the reorder vacated',
    );
    expect(
      [layout.startOf(0), layout.startOf(2), layout.startOf(3)],
      [0, 8, 12],
      reason: 'the displacement never propagates: 1, 3 and 4 are untouched',
    );
  });

  test('walking on gives every frame back, one at a time', () {
    // The gradient itself. Once 5 has crossed 2 it goes on left, and 2
    // walks home behind it one frame per frame until it arrives — never a
    // jump, and never a freeze.
    for (final (delta, runAt, followerAt) in const [
      (-12, 4, 6),
      (-13, 3, 5),
      (-14, 2, 4),
    ]) {
      final layout = dragLastBlock(delta);
      expect(layout.startOf(4), runAt, reason: 'the hand holds the run');
      expect(
        layout.startOf(1),
        followerAt,
        reason: 'block 2 heads for frame 4 and gets as far along that road '
            'as the run at $runAt leaves open',
      );
    }
  });

  test('a run of two walks home as one, and so does everyone it passed', () {
    // 4+5 dragged together, back past 3 and 2.
    final layout = planBlockRunMove(
      slots: row,
      runStart: 3,
      runEnd: 4,
      frameDelta: -6,
    );

    expect(layout.order, [0, 1, 3, 4, 2]);
    expect(layout.startOf(3), 6, reason: 'the head of the run is at the hand');
    expect(
      layout.startOf(4),
      10,
      reason: 'and the run keeps its own internal shape, gap included',
    );
    expect(
      [layout.startOf(0), layout.startOf(1), layout.startOf(2)],
      [0, 4, 12],
      reason: '3 is pushed past its own 8 by the run and stops at 12; 1 and '
          '2 were never touched at all',
    );
  });
}
