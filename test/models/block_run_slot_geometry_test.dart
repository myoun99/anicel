import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/block_run_move.dart';

/// The two conversions every block-run planner opens and closes with:
/// slots (gap, length) to absolute starts, and starts back to gaps. They
/// are inverses, and each planner used to carry its own copy of both.
void main() {
  List<BlockMoveSlot> slots(List<(int, int)> pairs) => [
    for (final pair in pairs) (leadingGap: pair.$1, length: pair.$2),
  ];

  test('starts accumulate gap then length, from frame 0', () {
    expect(slotStartsOf(slots([(0, 4), (2, 3), (0, 1)])), [0, 6, 9]);
    expect(slotStartsOf(slots([(5, 2), (1, 1)])), [5, 8]);
    expect(slotStartsOf(const []), isEmpty);
  });

  test('gaps are the distance from the previous end, frame 0 first', () {
    expect(leadingGapsOf(starts: [0, 6, 9], lengths: [4, 3, 1]), [0, 2, 0]);
    expect(leadingGapsOf(starts: [5, 8], lengths: [2, 1]), [5, 1]);
    expect(leadingGapsOf(starts: const [], lengths: const []), isEmpty);
  });

  test('gaps of starts of slots are the slots\' own gaps', () {
    for (final sample in [
      slots([(0, 4), (0, 4), (0, 4)]),
      slots([(18, 3), (0, 2), (7, 1)]),
      slots([(3, 1)]),
      slots([(0, 10), (5, 1), (0, 1), (2, 6)]),
    ]) {
      final lengths = [for (final slot in sample) slot.length];
      expect(leadingGapsOf(starts: slotStartsOf(sample), lengths: lengths), [
        for (final slot in sample) slot.leadingGap,
      ]);
    }
  });

  test('an overlap reads as a negative gap rather than being hidden', () {
    expect(leadingGapsOf(starts: [0, 3], lengths: [4, 1]), [0, -1]);
  });
}
