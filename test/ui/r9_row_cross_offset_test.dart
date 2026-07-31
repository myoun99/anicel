import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cross_offset.dart';

/// R9 #25 — resolving a pointer's cross-axis offset to a row.
///
/// The bug this replaces: the shared gesture divided the offset by ONE row
/// height (the height of the row the drag started on) and handed up a row
/// COUNT. On the storyboard rail, where an SE row is 30px and the V row is
/// 28–160px, that under-counted every row of a different size — dragging
/// UP from a tall V row stalled partway, while dragging DOWN survived only
/// because the end clamp caught it.
void main() {
  group('uniform pitch — what the timeline and x-sheet use', () {
    test('floors toward the row the pointer is inside', () {
      int at(double offset) =>
          uniformRowDeltaForCrossOffset(crossOffset: offset, rowExtent: 28);

      expect(at(0), 0);
      expect(at(27.9), 0);
      expect(at(28), 1);
      expect(at(-0.1), -1, reason: 'anything above this row is already -1');
      expect(at(-28), -1);
      expect(at(-28.1), -2);
    });

    test('a zero extent cannot divide, so nothing moves', () {
      expect(
        uniformRowDeltaForCrossOffset(crossOffset: 500, rowExtent: 0),
        0,
      );
    });
  });

  group('height table — what the storyboard rail needs', () {
    // The shape that produced the report: four SE rows of 30 stacked above
    // a V row the user had enlarged. Index 4 is the V row.
    List<double> rail({required double vHeight}) => [30, 30, 30, 30, vHeight];

    test('UP from a TALL V row still reaches every S row — the report', () {
      // 4 rows up from the V row is S4, the topmost. The old scalar divided
      // by the V row's own height, so with a 124px V row it read 120px of
      // travel as -1 (S1) and stopped there.
      for (final vHeight in [28.0, 64.0, 124.0, 160.0]) {
        final heights = rail(vHeight: vHeight);
        expect(
          rowIndexForCrossOffset(
            crossOffset: -120,
            anchorIndex: 4,
            heights: heights,
          ),
          0,
          reason: 'V row height $vHeight must not change how far 120px of '
              'travel reaches — the rows it crosses are 30 each',
        );
        expect(
          rowIndexForCrossOffset(
            crossOffset: -30,
            anchorIndex: 4,
            heights: heights,
          ),
          3,
          reason: 'one S row up, whatever the V row measures',
        );
      }
    });

    test('DOWN from an S row reaches the V row', () {
      final heights = rail(vHeight: 64);
      expect(
        rowIndexForCrossOffset(
          crossOffset: 30,
          anchorIndex: 3,
          heights: heights,
        ),
        4,
      );
      expect(
        rowIndexForCrossOffset(crossOffset: 0, anchorIndex: 3, heights: heights),
        3,
        reason: 'still inside the anchor row',
      );
    });

    test('the two directions agree — the asymmetry is gone', () {
      final heights = rail(vHeight: 124);
      // The four S rows are 30 each, so the V row's top is 120px below the
      // top row's top. That ONE distance has to answer the same both ways —
      // which is exactly what the old scalar could not do, because it
      // divided by a different number depending on where you started.
      expect(
        rowIndexForCrossOffset(
          crossOffset: 120,
          anchorIndex: 0,
          heights: heights,
        ),
        4,
        reason: 'down the whole rail lands on the V row',
      );
      expect(
        rowIndexForCrossOffset(
          crossOffset: -120,
          anchorIndex: 4,
          heights: heights,
        ),
        0,
        reason: 'and the same 120px back up lands on the top row',
      );
    });

    test('running off either end stops at the last row', () {
      final heights = rail(vHeight: 64);
      expect(
        rowIndexForCrossOffset(
          crossOffset: -9999,
          anchorIndex: 4,
          heights: heights,
        ),
        0,
      );
      expect(
        rowIndexForCrossOffset(
          crossOffset: 9999,
          anchorIndex: 0,
          heights: heights,
        ),
        4,
      );
    });

    test('rows a drag cannot land on still take up their space', () {
      // A twirled-open SE row wedges an audio strip (36) and a transform
      // strip (26) below it. Reaching past them must account for their
      // pixels, or the head lands short.
      final heights = <double>[30, 36, 26, 30, 64];
      expect(
        rowIndexForCrossOffset(
          crossOffset: 30 + 36 + 26,
          anchorIndex: 0,
          heights: heights,
        ),
        3,
        reason: 'the strips are crossed, not skipped',
      );
    });

    test('an empty table and an out-of-range anchor are survivable', () {
      expect(
        rowIndexForCrossOffset(crossOffset: 10, anchorIndex: 0, heights: const []),
        0,
      );
      expect(
        rowIndexForCrossOffset(
          crossOffset: 0,
          anchorIndex: 99,
          heights: const [30, 30],
        ),
        1,
      );
    });
  });
}
