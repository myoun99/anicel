import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/storyboard_coverage.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';

/// The storyboard row TILES its cut: no gaps, no overlaps, every frame in
/// exactly one cell. These drive the rule from the store's side, because
/// the whole point is that no stored shape can express a hole.
SplayTreeMap<int, TimelineExposure> _timeline(
  Map<int, TimelineExposure> entries,
) => SplayTreeMap<int, TimelineExposure>.of(entries);

TimelineExposure _drawing(String id, {int length = 1}) =>
    TimelineExposure.drawing(FrameId(id), length: length);

void main() {
  test('no layer at all is ONE cell over the whole cut', () {
    final cells = storyboardCoverageCells(timeline: null, cutDuration: 12);

    expect(cells, [
      const StoryboardCoverageCell(
        startIndex: 0,
        endIndexExclusive: 12,
        frameId: null,
      ),
    ]);
  });

  test('an empty timeline degenerates into the same one cell', () {
    final cells = storyboardCoverageCells(
      timeline: _timeline({}),
      cutDuration: 12,
    );

    expect(cells.single.startIndex, 0);
    expect(cells.single.endIndexExclusive, 12);
    expect(cells.single.frameId, isNull);
  });

  test('one drawing owns the WHOLE cut, wherever it starts — one drawing '
      'is one panel until the cut is divided', () {
    final cells = storyboardCoverageCells(
      timeline: _timeline({3: _drawing('a')}),
      cutDuration: 12,
    );

    expect(cells, [
      const StoryboardCoverageCell(
        startIndex: 0,
        endIndexExclusive: 12,
        frameId: FrameId('a'),
      ),
    ]);
  });

  test('each block runs to the NEXT division, the last to the cut end — '
      'stored lengths do not leave holes behind', () {
    final cells = storyboardCoverageCells(
      // Lengths deliberately too short to tile: the rule is the division,
      // not the stored length.
      timeline: _timeline({
        0: _drawing('a'),
        4: _drawing('b'),
        9: _drawing('c'),
      }),
      cutDuration: 12,
    );

    expect(cells.map((cell) => cell.startIndex), [0, 4, 9]);
    expect(cells.map((cell) => cell.endIndexExclusive), [4, 9, 12]);
    expect(cells.map((cell) => cell.frameId), const [
      FrameId('a'),
      FrameId('b'),
      FrameId('c'),
    ]);
  });

  test('the cells tile the cut exactly: every frame lands in one', () {
    final timeline = _timeline({
      0: _drawing('a'),
      4: _drawing('b', length: 2),
      9: _drawing('c'),
    });

    for (var frame = 0; frame < 12; frame += 1) {
      final covering = [
        for (final cell in storyboardCoverageCells(
          timeline: timeline,
          cutDuration: 12,
        ))
          if (cell.covers(frame)) cell,
      ];
      expect(covering, hasLength(1), reason: 'frame $frame');
    }
  });

  test('growing the cut lengthens the LAST cell and nothing else', () {
    final timeline = _timeline({0: _drawing('a'), 4: _drawing('b')});

    final before = storyboardCoverageCells(timeline: timeline, cutDuration: 8);
    final after = storyboardCoverageCells(timeline: timeline, cutDuration: 20);

    expect(before.map((cell) => cell.endIndexExclusive), [4, 8]);
    expect(after.map((cell) => cell.endIndexExclusive), [4, 20]);
    expect(after.first, before.first);
  });

  test('a division past the cut end makes no cell — the block is real data '
      'but the conte has no panel for it', () {
    final cells = storyboardCoverageCells(
      timeline: _timeline({0: _drawing('a'), 20: _drawing('over-the-end')}),
      cutDuration: 12,
    );

    expect(cells, [
      const StoryboardCoverageCell(
        startIndex: 0,
        endIndexExclusive: 12,
        frameId: FrameId('a'),
      ),
    ]);
  });

  test('a ghost is not a division: repeats are refused on this row, and a '
      'derived instance owns no panel', () {
    final cells = storyboardCoverageCells(
      timeline: _timeline({
        0: _drawing('a'),
        4: const TimelineExposure.drawing(FrameId('a'), length: 2, ghost: true),
      }),
      cutDuration: 12,
    );

    expect(cells, hasLength(1));
    expect(cells.single.endIndexExclusive, 12);
  });

  test('a zero-length cut has no cells at all', () {
    expect(
      storyboardCoverageCells(
        timeline: _timeline({0: _drawing('a')}),
        cutDuration: 0,
      ),
      isEmpty,
    );
  });

  test('storyboardCellAt finds the covering cell, and nothing outside', () {
    final timeline = _timeline({0: _drawing('a'), 4: _drawing('b')});

    expect(
      storyboardCellAt(
        timeline: timeline,
        cutDuration: 12,
        frameIndex: 7,
      )?.frameId,
      const FrameId('b'),
    );
    expect(
      storyboardCellAt(timeline: timeline, cutDuration: 12, frameIndex: 12),
      isNull,
    );
  });

  group('moving a division', () {
    test('the cut START is not a division: the first key refuses to move', () {
      expect(
        storyboardDivisionBounds(
          timeline: _timeline({0: _drawing('a'), 4: _drawing('b')}),
          cutDuration: 12,
          divisionIndex: 0,
        ),
        isNull,
      );
    });

    test('a division travels between its neighbours, both cells keeping a '
        'frame', () {
      final bounds = storyboardDivisionBounds(
        timeline: _timeline({
          0: _drawing('a'),
          4: _drawing('b'),
          8: _drawing('c'),
        }),
        cutDuration: 12,
        divisionIndex: 4,
      );

      expect(bounds, (min: 1, max: 7));
    });

    test("the LAST division's room reaches to the cut end", () {
      expect(
        storyboardDivisionBounds(
          timeline: _timeline({0: _drawing('a'), 4: _drawing('b')}),
          cutDuration: 12,
          divisionIndex: 4,
        ),
        (min: 1, max: 11),
      );
    });

    test('two one-frame cells leave the edge exactly where it is — it is '
        'still an edge, it just has nowhere to go', () {
      expect(
        storyboardDivisionBounds(
          timeline: _timeline({0: _drawing('a'), 1: _drawing('b')}),
          cutDuration: 2,
          divisionIndex: 1,
        ),
        (min: 1, max: 1),
      );
    });

    test('a key that is not a division at all refuses', () {
      expect(
        storyboardDivisionBounds(
          timeline: _timeline({0: _drawing('a'), 4: _drawing('b')}),
          cutDuration: 12,
          divisionIndex: 5,
        ),
        isNull,
      );
    });

    test('the move is a RE-KEY: the neighbours stay put and the cells resize '
        'because coverage derives them', () {
      final moved = storyboardTimelineWithDivisionMoved(
        timeline: _timeline({
          0: _drawing('a', length: 4),
          4: _drawing('b', length: 4),
          8: _drawing('c', length: 4),
        }),
        cutDuration: 12,
        divisionIndex: 4,
        newIndex: 2,
      )!;

      expect(moved.keys, [0, 2, 8]);
      expect(storyboardCoverageCells(timeline: moved, cutDuration: 12), const [
        StoryboardCoverageCell(
          startIndex: 0,
          endIndexExclusive: 2,
          frameId: FrameId('a'),
        ),
        StoryboardCoverageCell(
          startIndex: 2,
          endIndexExclusive: 8,
          frameId: FrameId('b'),
        ),
        StoryboardCoverageCell(
          startIndex: 8,
          endIndexExclusive: 12,
          frameId: FrameId('c'),
        ),
      ]);
    });

    test('the STORED lengths follow, so the shared verbs read the same '
        'picture the conte does', () {
      final moved = storyboardTimelineWithDivisionMoved(
        timeline: _timeline({
          0: _drawing('a', length: 4),
          4: _drawing('b', length: 8),
        }),
        cutDuration: 12,
        divisionIndex: 4,
        newIndex: 9,
      )!;

      expect(moved[0]!.length, 9);
      expect(moved[9]!.length, 3);
    });

    test('a drag past a neighbour CLAMPS instead of reordering', () {
      final moved = storyboardTimelineWithDivisionMoved(
        timeline: _timeline({
          0: _drawing('a', length: 4),
          4: _drawing('b', length: 4),
          8: _drawing('c', length: 4),
        }),
        cutDuration: 12,
        divisionIndex: 4,
        newIndex: -50,
      )!;

      expect(moved.keys, [0, 1, 8]);
    });

    test('the inbetween dots go with the frames they mark, across the '
        'division in either direction', () {
      // `a` holds [0,6) with a dot on frame 4; `b` holds [6,12) with one on
      // frame 7. Pushing the division to 9 puts frame 7 inside a's cell.
      final pushed = storyboardTimelineWithDivisionMoved(
        timeline: _timeline({
          0: TimelineExposure.drawing(
            const FrameId('a'),
            length: 6,
            breakdownOffsets: const [4],
          ),
          6: TimelineExposure.drawing(
            const FrameId('b'),
            length: 6,
            breakdownOffsets: const [1],
          ),
        }),
        cutDuration: 12,
        divisionIndex: 6,
        newIndex: 9,
      )!;

      // Frame 7 (b's offset 1) now sits in a's cell, as a's offset 7.
      expect(pushed[0]!.breakdownOffsets, [4, 7]);
      expect(pushed[9]!.breakdownOffsets, isEmpty);

      // And the other way: pulling the division back to 3 hands a's dot on
      // frame 4 to b, one frame past its new start.
      final pulled = storyboardTimelineWithDivisionMoved(
        timeline: _timeline({
          0: TimelineExposure.drawing(
            const FrameId('a'),
            length: 6,
            breakdownOffsets: const [4],
          ),
          6: _drawing('b', length: 6),
        }),
        cutDuration: 12,
        divisionIndex: 6,
        newIndex: 3,
      )!;

      expect(pulled[0]!.breakdownOffsets, isEmpty);
      expect(pulled[3]!.breakdownOffsets, [1]);
    });
  });
}
