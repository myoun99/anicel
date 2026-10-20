import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';

/// A ROW'S LANES OF BLOCKS — its exposures, its instruction events, and for
/// a folder the runs its members make — are ONE list, read by the drag that
/// snaps to them ([snapSpanToRowsBlocks]) and by the wash that stands on
/// them ([standingUnitOnRow], F-248 · F-268).
///
/// Each lane's own resolver was pinned, and the rule that snaps a span to a
/// lane was (`range_snap_test`). That a ROW reads each of its lanes was not:
/// measured 2026-10-06, taking the instruction lane or the folder lane out of
/// the list passed every test that names them.
void main() {
  const id = LayerId('row');

  // [3, 6) drawn, cells 6 and 7 empty, and an instruction event over [8, 13).
  final row =
      Layer(
        id: id,
        name: 'row',
        frames: [Frame(id: const FrameId('a'), duration: 1, strokes: const [])],
        timeline: {
          3: const TimelineExposure.drawing(FrameId('a'), length: 3),
        },
      ).copyWith(
        instructions: {
          8: const InstructionEvent(instructionId: 'pan', length: 5),
        },
      );

  ({int start, int end})? snapped(
    int cell, {
    List<({int start, int endExclusive})> runs = const [],
  }) {
    final span = snapSpanToRowsBlocks(
      rows: [(layer: row, runs: runs)],
      anchorIndex: cell,
      headIndex: cell,
    );
    return span == null
        ? null
        : (start: span.startIndex, end: span.endIndexExclusive);
  }

  test('a drag over one cell of an exposure block takes the block', () {
    expect(snapped(4), (start: 3, end: 6));
    expect(snapped(6), (start: 6, end: 7), reason: 'an empty cell is itself');
  });

  test('…and over one cell of an instruction event, the event (UI-R22 #4)', () {
    expect(snapped(10), (start: 8, end: 13));
  });

  test('a folder row snaps to the runs its members make (R9 #1) — and a row '
      'handed none snaps to none', () {
    // Over the row's two empty cells, clear of its own blocks.
    const runs = [(start: 6, endExclusive: 8)];
    expect(snapped(7, runs: runs), (start: 6, end: 8));
    expect(snapped(7), (start: 7, end: 8), reason: '⛔전제: no lane, no snap');
    expect(
      snapped(4, runs: runs),
      (start: 3, end: 6),
      reason: 'the row\'s own lanes still answer beside it',
    );
  });

  test('a band over two rows cuts neither row\'s block', () {
    // A band over [7, 10): the second row's block [6, 8) takes its start to
    // 6, the first row's event over [8, 13) its end to 13 — neither row
    // alone reaches both.
    final other = Layer(
      id: const LayerId('other'),
      name: 'other',
      frames: [Frame(id: const FrameId('b'), duration: 1, strokes: const [])],
      timeline: {
        6: const TimelineExposure.drawing(FrameId('b'), length: 2),
      },
    );
    final band = snapSpanToRowsBlocks(
      rows: [(layer: row, runs: const []), (layer: other, runs: const [])],
      anchorIndex: 7,
      headIndex: 9,
    );
    expect(band, (startIndex: 6, endIndexExclusive: 13));
    expect(
      snapSpanToRowsBlocks(rows: const [], anchorIndex: 9, headIndex: 7),
      (startIndex: 7, endIndexExclusive: 10),
      reason: 'no rows — a band of lanes alone — is the raw span',
    );
  });

  test('what a row stands on is what a click there takes — and it says '
      'whether that is a block', () {
    expect(standingUnitOnRow(row, 4), (
      startIndex: 3,
      endIndexExclusive: 6,
      block: true,
    ));
    expect(standingUnitOnRow(row, 6), (
      startIndex: 6,
      endIndexExclusive: 7,
      block: false,
    ));
    expect(standingUnitOnRow(row, 10), (
      startIndex: 8,
      endIndexExclusive: 13,
      block: true,
    ));
  });
}
