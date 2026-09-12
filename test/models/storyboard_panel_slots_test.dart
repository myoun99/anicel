import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/block_run_lead_edge.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/storyboard_panel_slots.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// THE TRACK AS PANELS — the unit that lets ONE lead-edge rule serve the
/// storyboard too (I-21 ②, 유저 2026-09-12: 「앞 컷이 그냥 컷블록이면 컷이
/// 1코마될때까지 미는거지 … 근데 그 컷 블록에 콘티블록있으면 그 블록의
/// 헤드까지. 이것도 똑같은 법인거지」).
void main() {
  const cutA = CutId('a');
  const cutB = CutId('b');

  StoryboardCutInput cut(
    CutId id, {
    required int duration,
    int gap = 0,
    List<int> keys = const [],
  }) => (
    id: id,
    leadingGapFrames: gap,
    duration: duration,
    divisionKeys: keys,
  );

  test('a cut with no conte row is ONE panel — its whole duration', () {
    final panels = panelSlotsOfCuts([cut(cutA, duration: 12, gap: 3)]);

    expect(panels, hasLength(1));
    expect(panels.single.panelIndex, 0);
    expect(panels.single.slot, (leadingGap: 3, length: 12));
  });

  test('a cut with conte keys is its panels, and only the FIRST carries the '
      'cut gap', () {
    final panels = panelSlotsOfCuts([
      cut(cutA, duration: 12, gap: 2, keys: [0, 4, 9]),
    ]);

    expect(
      [for (final panel in panels) panel.slot],
      [
        (leadingGap: 2, length: 4),
        (leadingGap: 0, length: 5),
        (leadingGap: 0, length: 3),
      ],
      reason: 'panels tile the cut, so only the first one has a gap in front',
    );
  });

  test('the boundary between two CUTS is just another boundary', () {
    // Cut A: two panels [0,4)[4,8). Cut B: one panel of 6, glued.
    final before = [
      cut(cutA, duration: 8, keys: [0, 4]),
      cut(cutB, duration: 6),
    ];
    final panels = panelSlotsOfCuts(before);

    // Drag cut B's front edge two frames forward: the block in front is
    // A's LAST panel, and it gives the frames — A's other panel never moves.
    final layout = planBlockRunLeadEdge(
      slots: [for (final panel in panels) panel.slot],
      targetIndex: 2,
      frameDelta: -2,
    );

    expect(layout.lengths, [4, 2, 8]);
    final read = cutsFromPanelLayout(
      panels: panels,
      leadingGaps: layout.leadingGaps,
      lengths: layout.lengths,
      before: before,
    );
    expect(
      read.durations,
      {cutA: 6, cutB: 8},
      reason: 'the film keeps its total length — one cut gave, one took',
    );
    expect(read.gaps, isEmpty, reason: 'nothing opened or closed a gap');
  });

  test('a cut with NO conte row gives from the cut itself, down to one '
      'frame', () {
    final before = [cut(cutA, duration: 3), cut(cutB, duration: 4)];
    final panels = panelSlotsOfCuts(before);

    final layout = planBlockRunLeadEdge(
      slots: [for (final panel in panels) panel.slot],
      targetIndex: 1,
      frameDelta: -999,
    );

    final read = cutsFromPanelLayout(
      panels: panels,
      leadingGaps: layout.leadingGaps,
      lengths: layout.lengths,
      before: before,
    );
    expect(
      read.durations,
      {cutA: 1, cutB: 6},
      reason: 'the cut in front is one panel, so it is squeezed to one frame',
    );
  });

  /// ↩️WHAT THE RETIRED LAW'S PIN GUARDED, kept because the property is
  /// still real: a panel index nothing matches must read as "there is no
  /// such block", never as an index into somebody else's list.
  ///
  /// The old guard lived in `_panelLeadBounds` — a mutation survivor from
  /// 2026-09-03, where one `||` became `&&` and an index past the last
  /// panel read straight into the key list. Flattening answers it
  /// structurally: the drag looks its target up BY (cut, panel), and a
  /// pair nobody carries is simply not found.
  test('a panel index nothing carries is not found — no plan comes of it', () {
    final panels = panelSlotsOfCuts([
      cut(cutA, duration: 8, keys: [0, 4]),
      cut(cutB, duration: 6),
    ]);

    for (final missing in [2, 7, -1]) {
      expect(
        panels.indexWhere(
          (panel) => panel.cutId == cutA && panel.panelIndex == missing,
        ),
        -1,
        reason: 'cut A has two panels; $missing is not one of them',
      );
    }
    expect(
      panels.indexWhere((panel) => panel.cutId == const CutId('gone')),
      -1,
      reason: 'a cut that is not in the run carries no panels either',
    );
  });

  test('reading back is sparse: an untouched cut says nothing', () {
    final before = [
      cut(cutA, duration: 8, keys: [0, 4]),
      cut(cutB, duration: 6, gap: 2),
    ];
    final panels = panelSlotsOfCuts(before);

    final read = cutsFromPanelLayout(
      panels: panels,
      leadingGaps: [for (final panel in panels) panel.slot.leadingGap],
      lengths: [for (final panel in panels) panel.slot.length],
      before: before,
    );

    expect(read.durations, isEmpty);
    expect(read.gaps, isEmpty);
  });

  test('the conte row reads the panel lengths back as its keys', () {
    final row = SplayTreeMap<int, TimelineExposure>.of({
      0: const TimelineExposure.drawing(FrameId('p0'), length: 4),
      4: const TimelineExposure.drawing(FrameId('p1'), length: 6),
    });

    final next = conteTimelineFromPanels(
      timeline: row,
      panelLengths: [6, 4],
    );

    expect(next, isNotNull);
    expect(next!.keys.toList(), [0, 6], reason: 'the boundary moved');
    expect(next[0]!.length, 6);
    expect(next[6]!.length, 4);
    expect(
      next[0]!.frameId,
      const FrameId('p0'),
      reason: 'a panel keeps its picture — only its timing changed',
    );
  });

  test('a row the panels do not match is refused rather than guessed', () {
    final row = SplayTreeMap<int, TimelineExposure>.of({
      0: const TimelineExposure.drawing(FrameId('p0'), length: 4),
    });

    expect(
      conteTimelineFromPanels(timeline: row, panelLengths: [2, 2]),
      isNull,
      reason: 'two panels for one block is not this function\'s to repair',
    );
    expect(
      conteTimelineFromPanels(timeline: null, panelLengths: [4]),
      isNull,
    );
  });
}
