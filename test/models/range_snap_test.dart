import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/range_snap.dart';

/// THE block-snapping rule, tested on its own material rather than through
/// a layer or a track — the point of extracting it is that both axes get
/// exactly these answers.
/// Test material: a plain sorted, non-overlapping list answering as a lane.
RangeBlock? _blockCoveringIn(List<RangeBlock> lane, int index) {
  for (final block in lane) {
    if (index >= block.startIndex && index < block.endIndexExclusive) {
      return block;
    }
  }
  return null;
}

void main() {
  RangeBlockAt laneOf(List<RangeBlock> blocks) =>
      (index) => _blockCoveringIn(blocks, index);

  group('snapSpanToBlocks', () {
    test('a span inside one block extends through the whole block', () {
      final lane = laneOf(const [
        RangeBlock(startIndex: 0, endIndexExclusive: 6),
      ]);

      final span = snapSpanToBlocks(
        lanes: [lane],
        anchorIndex: 2,
        headIndex: 3,
      );

      expect(span?.startIndex, 0);
      expect(span?.endIndexExclusive, 6);
    });

    test('a span straddling two blocks covers both whole', () {
      final lane = laneOf(const [
        RangeBlock(startIndex: 0, endIndexExclusive: 4),
        RangeBlock(startIndex: 4, endIndexExclusive: 9),
      ]);

      final span = snapSpanToBlocks(
        lanes: [lane],
        anchorIndex: 3,
        headIndex: 5,
      );

      expect(span?.startIndex, 0);
      expect(span?.endIndexExclusive, 9);
    });

    test('empty cells between blocks neither extend nor break the span', () {
      final lane = laneOf(const [
        RangeBlock(startIndex: 0, endIndexExclusive: 2),
        RangeBlock(startIndex: 6, endIndexExclusive: 8),
      ]);

      final span = snapSpanToBlocks(
        lanes: [lane],
        anchorIndex: 3,
        headIndex: 4,
      );

      expect(span?.startIndex, 3);
      expect(span?.endIndexExclusive, 5);
    });

    test('a ghost block is landed on but never extends the span', () {
      final lane = laneOf(const [
        RangeBlock(
          startIndex: 0,
          endIndexExclusive: 6,
          extendsSelection: false,
        ),
      ]);

      final span = snapSpanToBlocks(
        lanes: [lane],
        anchorIndex: 2,
        headIndex: 3,
      );

      expect(span?.startIndex, 2);
      expect(span?.endIndexExclusive, 4);
    });

    test('lanes grow each other until stable', () {
      // Growing for lane A uncovers a block in lane B, whose growth then
      // uncovers more of A — the answer needs the repeat, not one pass.
      final laneA = laneOf(const [
        RangeBlock(startIndex: 0, endIndexExclusive: 2),
        RangeBlock(startIndex: 4, endIndexExclusive: 6),
      ]);
      final laneB = laneOf(const [
        RangeBlock(startIndex: 1, endIndexExclusive: 5),
      ]);

      final span = snapSpanToBlocks(
        lanes: [laneA, laneB],
        anchorIndex: 4,
        headIndex: 4,
      );

      expect(span?.startIndex, 0);
      expect(span?.endIndexExclusive, 6);
    });

    test('a span clamps at frame zero', () {
      final lane = laneOf(const <RangeBlock>[]);

      final span = snapSpanToBlocks(
        lanes: [lane],
        anchorIndex: -5,
        headIndex: 2,
      );

      expect(span?.startIndex, 0);
      expect(span?.endIndexExclusive, 3);
    });
  });

}
