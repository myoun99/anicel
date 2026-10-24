import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/block_row_swap.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// F-384: what a row does with the blocks a move sends back to it, read
/// without a layer around it — so a block left standing on another is a
/// wrong answer here, not a row the layer refuses to hold.
void main() {
  TimelineExposure cel(String id, int length) =>
      TimelineExposure.drawing(FrameId(id), length: length);
  TimelineDrawingBlock block(int start, String id, int length) =>
      TimelineDrawingBlock(startIndex: start, entry: cel(id, length));
  Map<int, String> shown(Map<int, TimelineExposure> row) => {
    for (final MapEntry(:key, :value) in row.entries)
      key: value.frameId!.value,
  };

  group('a row taking blocks back (timelineTakingBack)', () {
    test('each lands on its own frames, and a block of the row it reaches '
        'makes way past it — one it reaches from before too', () {
      final row = timelineTakingBack(
        {0: cel('A', 3), 6: cel('C', 2)},
        [block(2, 'B', 2)],
      );
      expect(shown(row), {2: 'B', 4: 'A', 7: 'C'});
    });

    test('the empty space absorbs the push before the next block moves', () {
      final row = timelineTakingBack(
        {0: cel('A', 3), 10: cel('C', 2)},
        [block(1, 'B', 2)],
      );
      expect(shown(row), {1: 'B', 3: 'A', 10: 'C'});
    });

    test('a block it does not reach keeps its frames', () {
      final row = timelineTakingBack(
        {0: cel('A', 2), 8: cel('C', 2)},
        [block(3, 'B', 2)],
      );
      expect(shown(row), {0: 'A', 3: 'B', 8: 'C'});
    });

    test('blocks sent back are taken in frame order, whatever order they '
        'come in', () {
      final row = timelineTakingBack(
        {0: cel('A', 2)},
        [block(2, 'B2', 1), block(0, 'B1', 1)],
      );
      expect(shown(row), {0: 'B1', 2: 'B2', 3: 'A'});
    });
  });

  group('the blocks a landing lands on (blocksLandedOn)', () {
    final row = [block(0, 'A', 2), block(4, 'B', 2), block(8, 'C', 2)];

    test('a block the spans overlap is landed on; one only touching them '
        'is not', () {
      expect(
        blocksLandedOn(row, [(start: 2, length: 2)]).map((b) => b.frameId),
        isEmpty,
      );
      expect(
        blocksLandedOn(row, [(start: 1, length: 4)]).map((b) => b.frameId),
        [const FrameId('A'), const FrameId('B')],
      );
    });

    test('each span alone — a block in the gap between two is not landed '
        'on', () {
      expect(
        blocksLandedOn(row, [
          (start: 1, length: 2),
          (start: 9, length: 1),
        ]).map((b) => b.frameId),
        [const FrameId('A'), const FrameId('C')],
      );
    });
  });
}
