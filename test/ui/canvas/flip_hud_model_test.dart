import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';

/// The flip HUD's slot model — the one piece that turns a row's content
/// into columns. Everything the window draws hangs off these, so the
/// contract is asserted here rather than through a painter.
void main() {
  // A ► 2 empty, block '1' (3f), block '2' (2f), 3 empty, block '3' (1f),
  // then 4 empty to the end. 15 frames.
  FlipHudRow celRow() => const FlipHudRow(
    name: 'A',
    kind: LayerKind.animation,
    runs: [
      FlipHudRun(startIndex: 2, length: 3, label: '1'),
      FlipHudRun(startIndex: 5, length: 2, label: '2'),
      FlipHudRun(startIndex: 10, length: 1, label: '3'),
    ],
  );

  group('block slots', () {
    test('a run is ONE column and every uncovered frame is its own', () {
      final slots = flipHudBlockSlots(celRow(), 15);

      expect(slots.map((slot) => (slot.startIndex, slot.frames, slot.filled)), [
        (0, 1, false),
        (1, 1, false),
        (2, 3, true),
        (5, 2, true),
        (7, 1, false),
        (8, 1, false),
        (9, 1, false),
        (10, 1, true),
        (11, 1, false),
        (12, 1, false),
        (13, 1, false),
        (14, 1, false),
      ]);
    });

    test('a held frame belongs to its block, not to a column of its own', () {
      final slots = flipHudBlockSlots(celRow(), 15);

      // Frames 3 and 4 are the hold of block '1'.
      expect(flipHudSlotIndexAt(slots, 2), 2);
      expect(flipHudSlotIndexAt(slots, 3), 2);
      expect(flipHudSlotIndexAt(slots, 4), 2);
      expect(flipHudSlotIndexAt(slots, 5), 3);
    });

    test('a row with no content is all empty columns', () {
      const bare = FlipHudRow(
        name: 'B',
        kind: LayerKind.animation,
        runs: <FlipHudRun>[],
      );

      final slots = flipHudBlockSlots(bare, 4);

      expect(slots.length, 4);
      expect(slots.every((slot) => !slot.filled), isTrue);
    });
  });

  group('frame slots', () {
    test('one column per frame, each carrying whatever covers it', () {
      final slots = flipHudFrameSlots(celRow(), 15);

      expect(slots.length, 15);
      expect(slots[2].run?.label, '1');
      // The hold carries the same run, so the painter can span one body.
      expect(slots[3].run, same(slots[2].run));
      expect(slots[7].run, isNull);
    });
  });

  group('culling to the window', () {
    test('keeps the head of a block whose start has scrolled out', () {
      // One block over the whole cut: at frame 30 its head is far off the
      // left of a five-column window. Only the head draws the body, so
      // dropping it would leave bare grid where a block plainly is.
      const long = FlipHudRow(
        name: 'A',
        kind: LayerKind.animation,
        runs: [FlipHudRun(startIndex: 0, length: 40, label: '1')],
      );
      final slots = flipHudFrameSlots(long, 40);

      expect(flipHudFirstPaintedIndex(slots, 28), 0);
    });

    test('leaves an empty column where it found it', () {
      final slots = flipHudFrameSlots(celRow(), 15);

      // Frame 8 is mid-gap: nothing spans it, so nothing to walk back to.
      expect(flipHudFirstPaintedIndex(slots, 8), 8);
    });

    test('walks back only to the head, not past it', () {
      final slots = flipHudFrameSlots(celRow(), 15);

      // Frame 4 is the hold of the block that starts at 2.
      expect(flipHudFirstPaintedIndex(slots, 4), 2);
      // On the block axis a run is already one column — nothing to do.
      expect(flipHudFirstPaintedIndex(flipHudBlockSlots(celRow(), 15), 3), 3);
    });

    test('clamps a window that has run off either end', () {
      final slots = flipHudFrameSlots(celRow(), 15);

      expect(flipHudFirstPaintedIndex(slots, -4), 0);
      // Past the end clamps to the last column — which here is empty, so
      // there is no head to walk back to.
      expect(flipHudFirstPaintedIndex(slots, 99), 14);
      expect(flipHudFirstPaintedIndex(const <FlipHudSlot>[], 3), 0);

      // The same clamp on a row whose last block runs to the end walks
      // back to that block's head.
      const trailing = FlipHudRow(
        name: 'C',
        kind: LayerKind.animation,
        runs: [FlipHudRun(startIndex: 6, length: 9, label: '9')],
      );
      expect(flipHudFirstPaintedIndex(flipHudFrameSlots(trailing, 15), 99), 6);
    });
  });

  group('the timesheet X', () {
    test('marks the first cell of each empty stretch only', () {
      final row = celRow();

      expect(row.emptyRunStartsAt(0), isTrue);
      expect(row.emptyRunStartsAt(1), isFalse);
      expect(row.emptyRunStartsAt(7), isTrue);
      expect(row.emptyRunStartsAt(8), isFalse);
      expect(row.emptyRunStartsAt(11), isTrue);
      // A covered cell never starts an empty run.
      expect(row.emptyRunStartsAt(2), isFalse);
    });
  });

  group('contentKey — the haptic subject', () {
    FlipHudSnapshot snapshotAt(int frameIndex, {int rowIndex = 0}) =>
        FlipHudSnapshot(
          rows: [
            celRow(),
            const FlipHudRow(
              name: 'B',
              kind: LayerKind.animation,
              runs: [FlipHudRun(startIndex: 2, length: 3, label: '1')],
            ),
          ],
          rowIndex: rowIndex,
          frameIndex: frameIndex,
          frameCount: 15,
        );

    test('holds steady across a block and changes between blocks', () {
      expect(snapshotAt(2).contentKey, snapshotAt(4).contentKey);
      expect(snapshotAt(4).contentKey, isNot(snapshotAt(5).contentKey));
    });

    test('is null over empty space', () {
      expect(snapshotAt(0).contentKey, isNull);
      expect(snapshotAt(8).contentKey, isNull);
    });

    test('differs between rows even when the runs line up', () {
      // Both rows carry a run starting at frame 2; the row is part of the
      // identity, so stepping across still counts as a different picture.
      expect(
        snapshotAt(2, rowIndex: 0).contentKey,
        isNot(snapshotAt(2, rowIndex: 1).contentKey),
      );
    });
  });
}
