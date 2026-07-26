import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/row_block_shift.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';

/// PUSH and PULL are one rule for two axes: the blocks at or after an anchor
/// travel rigidly, carrying the empty space between them.
void main() {
  List<ShiftableBlock> blocks(List<(int, int)> spans) => [
    for (final span in spans) (startIndex: span.$1, endIndexExclusive: span.$2),
  ];

  group('blocksShiftedFrom', () {
    test('takes the blocks that START at or after the anchor', () {
      expect(
        blocksShiftedFrom(blocks([(0, 4), (4, 8), (10, 12)]), 4),
        blocks([(4, 8), (10, 12)]),
      );
    });

    test('a block STRADDLING the anchor stays put — the anchor is a '
        'boundary, and splitting a block is not a rigid move', () {
      expect(blocksShiftedFrom(blocks([(0, 8)]), 4), isEmpty);
    });
  });

  group('rowPullSlack', () {
    test('is the free space between the anchor and what moves', () {
      // a[0,4) — 6 free — b[10,12): b can come back 6.
      expect(
        rowPullSlack(blocks: blocks([(0, 4), (10, 12)]), anchorIndex: 10),
        6,
      );
    });

    test('is zero when the blocks already touch', () {
      expect(rowPullSlack(blocks: blocks([(0, 4), (4, 8)]), anchorIndex: 4), 0);
    });

    test('measures from what STAYS, so an anchor inside the gap gives the '
        'same answer', () {
      // The anchor says WHICH blocks move; how far they can come back is
      // decided by the block they would run into.
      expect(
        rowPullSlack(blocks: blocks([(0, 4), (10, 12)]), anchorIndex: 7),
        6,
      );
    });

    test('a row with nothing to move imposes no limit — the scope\'s other '
        'rows decide', () {
      expect(
        rowPullSlack(blocks: blocks([(0, 4)]), anchorIndex: 10),
        0x7fffffff,
      );
    });

    test('the leading gap is the slack when the anchor is the first block', () {
      expect(
        rowPullSlack(blocks: blocks([(5, 9), (9, 13)]), anchorIndex: 5),
        5,
      );
    });
  });

  group('timelineShiftedFrom', () {
    SplayTreeMap<int, TimelineExposure> timelineOf(
      Map<int, int> startToLength,
    ) {
      final map = SplayTreeMap<int, TimelineExposure>();
      startToLength.forEach((start, length) {
        map[start] = TimelineExposure.drawing(
          FrameId('frame-$start'),
          length: length,
        );
      });
      return map;
    }

    test('re-keys only the blocks at or after the anchor, keeping their '
        'spacing', () {
      final shifted = timelineShiftedFrom(
        timelineOf({0: 4, 4: 4, 12: 2}),
        anchorIndex: 4,
        delta: 3,
      );

      expect(shifted.keys, [0, 7, 15]);
      expect(shifted[7]!.length, 4);
    });

    test('a pull closes the gap without touching what stays', () {
      final shifted = timelineShiftedFrom(
        timelineOf({0: 4, 10: 2}),
        anchorIndex: 10,
        delta: -6,
      );

      expect(shifted.keys, [0, 4]);
    });

    test('zero delta hands back the same map', () {
      final timeline = timelineOf({0: 4});
      expect(
        timelineShiftedFrom(timeline, anchorIndex: 0, delta: 0),
        same(timeline),
      );
    });

    test('a shift past frame 0 is a programming error, not a clamp — the '
        'caller clamps with rowPullSlack', () {
      expect(
        () =>
            timelineShiftedFrom(timelineOf({2: 4}), anchorIndex: 2, delta: -5),
        throwsArgumentError,
      );
    });

    test('a shift that would overlap what stays is refused too', () {
      expect(
        () => timelineShiftedFrom(
          timelineOf({0: 4, 10: 2}),
          anchorIndex: 10,
          delta: -8,
        ),
        throwsArgumentError,
      );
    });
  });
}
