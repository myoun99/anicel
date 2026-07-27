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
}
