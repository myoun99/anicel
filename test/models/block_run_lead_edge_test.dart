import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/block_run_lead_edge.dart';
import 'package:anicel/src/models/block_run_move.dart';

/// R10 R4: the lead edge's contact rule, the frame axis's answer stated
/// once so the cut axis can give the same one.
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

  test('a GLUED predecessor translates wholesale and the head empties', () {
    // [0,4) [4,8) [8,12), all glued. Shrink the middle from the front by 2.
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 4), (0, 4)]),
      targetIndex: 1,
      frameDelta: 2,
    );

    expect(layout.lengths, [4, 2, 4], reason: 'only the target resizes');
    expect(
      startsOf(layout),
      [2, 6, 8],
      reason: 'the predecessor slid RIGHT keeping its length; the target '
          'ends where it always ended, so the follower never moved',
    );
    expect(
      layout.leadingGaps.first,
      2,
      reason: 'the difference lands at the HEAD of the axis',
    );
  });

  test('the whole glued CHAIN in front rides along', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 3), (0, 3), (0, 3), (0, 6)]),
      targetIndex: 3,
      frameDelta: 4,
    );

    expect(startsOf(layout), [4, 7, 10, 13]);
    expect(layout.lengths, [3, 3, 3, 2]);
    expect(layout.leadingGaps, [4, 0, 0, 0], reason: 'the chain stays glued');
  });

  test('a SEPARATED predecessor holds and its gap absorbs the move', () {
    // [0,4) then a 3-frame gap then [7,11).
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (3, 4)]),
      targetIndex: 1,
      frameDelta: 2,
    );

    expect(
      startsOf(layout),
      [0, 9],
      reason: 'nothing in front moves — the gap simply grows',
    );
    expect(layout.leadingGaps, [0, 5]);
  });

  test('growing forward eats the slack ahead and stops at frame 0 — a '
      'predecessor is reached, never overlapped', () {
    // [0,4) then a 2-frame gap then [6,10). There are exactly 2 frames of
    // slack in front, so no amount of pull can take more.
    for (final asked in [-4, -999]) {
      final layout = planBlockRunLeadEdge(
        slots: slots([(0, 4), (2, 4)]),
        targetIndex: 1,
        frameDelta: asked,
      );

      expect(
        startsOf(layout),
        [0, 4],
        reason: 'asked for $asked: the predecessor held at the head and the '
            'target came to rest against it',
      );
      expect(layout.lengths, [4, 6], reason: 'it grew by the slack, no more');
      expect(
        layout.leadingGaps,
        [0, 0],
        reason: 'they end up GLUED — the overlap clamp inside the walk is '
            'defensive, because the frame-0 wall always binds first',
      );
    }
  });

  test('shrinking stops at the minimum length', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 4)]),
      targetIndex: 1,
      frameDelta: 99,
      minLength: 2,
    );

    expect(layout.lengths[1], 2);
    expect(startsOf(layout), [2, 6]);
  });

  test('the FIRST slot has no predecessor — the head absorbs it directly', () {
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

  test('a block ALREADY under the floor refuses to shrink instead of '
      'throwing — the clamp bounds cannot cross', () {
    final layout = planBlockRunLeadEdge(
      slots: slots([(0, 4), (0, 2)]),
      targetIndex: 1,
      frameDelta: 3,
      minLength: 5,
    );

    expect(layout.lengths, [4, 2], reason: 'nothing shrinks below the floor');
    expect(startsOf(layout), [0, 4]);
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
