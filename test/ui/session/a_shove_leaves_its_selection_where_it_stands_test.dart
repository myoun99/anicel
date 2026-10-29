import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/block_shift.dart';
import '../../helpers/an_empty_drawing_row.dart';

/// 🚨F-264 — a shove leaves the selection that aimed it where it stands.
///
/// 🗣️유저 2026-10-02: 「선택범위 풀리는데 안풀리도록」 — it is kept. 🗣️유저
/// 2026-10-08: 「선택범위는 기준인 선택범위조차 이동해버리니까 계속해서
/// 당길수있는상황. 그래서 로직 통일해서 선택범위까지만 기준으로서
/// 당길수있게 … 자기 위치에 갱신」 — and it stays put, as the cell stood on
/// does: it is the anchor, and what lies under it now is what it holds.
/// ↩️It was carried the way its blocks went (10-06), so a pull it aimed
/// never ran out.
///
/// The storyboard's two — an S row's sounds and the cut row's cuts — are
/// pinned beside their shoves (`storyboard_selection_verbs_test.dart`).
void main() {
  BlockShift shoveOf(EditorSessionManager s) => s.blockShift;

  List<(int, int)> blocksOn(EditorSessionManager s, LayerId row) => [
    for (final entry
        in s.requireActiveCut.layers
            .firstWhere((layer) => layer.id == row)
            .timeline
            .entries)
      if (!entry.value.ghost) (entry.key, entry.key + entry.value.length!),
  ];

  (int, int)? cellsSelected(EditorSessionManager s) =>
      switch (s.frameRangeSelection.value) {
        final selection? => (selection.startIndex, selection.endIndexExclusive),
        null => null,
      };

  /// One row holding a block on each of [frames], the one on 4 selected.
  ({EditorSessionManager s, LayerId row}) blockOnFourSelected(
    List<int> frames,
  ) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final row = s.activeLayer!.id;
    for (final frame in frames) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
    }
    s.updateFrameRangeSelectionDrag(layerId: row, anchorIndex: 4, headIndex: 4);
    expect(cellsSelected(s), (4, 5), reason: '⛔전제');
    return (s: s, row: row);
  }

  test('pushed, the selection is still there, on the cells it covered', () {
    final (:s, :row) = blockOnFourSelected([0, 4]);

    shoveOf(s).pushFrames(2);

    expect(blocksOn(s, row), [(0, 1), (6, 7)]);
    expect(cellsSelected(s), (4, 5), reason: '「안풀리도록」, in its place');
    expect(s.frameRangeSelection.value!.spanLayerIds, [row]);
  });

  test('pulled twice, the block goes past the selection once and no further '
      '— the second pull finds nothing from its anchor on', () {
    final (:s, :row) = blockOnFourSelected([0, 4]);

    shoveOf(s).pullFrames(1);
    expect(blocksOn(s, row), [(0, 1), (3, 4)]);
    expect(shoveOf(s).canPullFrames(), isFalse, reason: '「선택범위까지만」');
    shoveOf(s).pullFrames(1);

    expect(blocksOn(s, row), [(0, 1), (3, 4)]);
    expect(cellsSelected(s), (4, 5));
  });

  test('a block after it is pulled up to it, and is what it holds then', () {
    final (:s, :row) = blockOnFourSelected([0, 4, 8]);

    // The button's presses, a frame each, as many as it takes.
    for (var press = 0; press < 6; press += 1) {
      shoveOf(s).pullFrames(1);
    }

    expect(blocksOn(s, row), [(0, 1), (3, 4), (4, 5)]);
    expect(cellsSelected(s), (4, 5), reason: 'the block from 8 under it now');
    expect(shoveOf(s).canPullFrames(), isFalse);
  });

  test('a longer block pulled into it is taken in whole — 「블록이 '
      '범위안에 들어오면 선택범위가 커져야」', () {
    final (:s, :row) = blockOnFourSelected([0, 4, 8]);
    s.clearTimelineSelections();
    s.selectFrameIndex(8);
    s.edgeDrag.setCommaForTimelineCursor(3);
    s.updateFrameRangeSelectionDrag(layerId: row, anchorIndex: 4, headIndex: 4);
    expect(blocksOn(s, row), [(0, 1), (4, 5), (8, 11)], reason: '⛔전제');

    for (var press = 0; press < 6; press += 1) {
      shoveOf(s).pullFrames(1);
    }

    expect(blocksOn(s, row), [(0, 1), (3, 4), (4, 7)]);
    expect(cellsSelected(s), (4, 7));
    expect(shoveOf(s).canPullFrames(), isFalse);
  });

  test('pushed, the block it holds is still its own, wherever it went', () {
    final (:s, :row) = blockOnFourSelected([0, 4]);
    s.clearTimelineSelections();
    s.selectFrameIndex(4);
    s.edgeDrag.setCommaForTimelineCursor(3);
    s.updateFrameRangeSelectionDrag(layerId: row, anchorIndex: 4, headIndex: 4);
    expect(cellsSelected(s), (4, 7), reason: '⛔전제: the block, whole');

    shoveOf(s).pushFrames(2);

    expect(blocksOn(s, row), [(0, 1), (6, 9)]);
    expect(cellsSelected(s), (4, 9));
  });

  test('a block pulled back past its start is no longer one it grows for — '
      'its start, the anchor, stays', () {
    final (:s, :row) = blockOnFourSelected([0, 4]);
    s.clearTimelineSelections();
    s.selectFrameIndex(4);
    s.edgeDrag.setCommaForTimelineCursor(3);
    s.updateFrameRangeSelectionDrag(layerId: row, anchorIndex: 4, headIndex: 4);
    expect(cellsSelected(s), (4, 7), reason: '⛔전제: the block, whole');

    shoveOf(s).pullFrames(1);

    expect(blocksOn(s, row), [(0, 1), (3, 6)]);
    expect(cellsSelected(s), (4, 7));
    expect(shoveOf(s).canPullFrames(), isFalse, reason: '「선택범위까지만」');
  });

  test('a band over several rows keeps every row, in its place, grown '
      'over the longest block it holds', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final lower = s.activeLayer!.id;
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame();
    addAnEmptyDrawingRow(s);
    final upper = s.activeLayer!.id;
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame();
    s.edgeDrag.setCommaForTimelineCursor(3);
    s.updateFrameRangeSelectionDrag(
      layerId: lower,
      anchorIndex: 4,
      headIndex: 4,
      headLayerId: upper,
    );
    final rows = s.frameRangeSelection.value!.spanLayerIds;
    expect(rows, unorderedEquals([lower, upper]), reason: '⛔전제');
    expect(cellsSelected(s), (4, 7), reason: '⛔전제: both blocks, whole');

    shoveOf(s).pushFrames(1);
    shoveOf(s).pushFrames(1);

    expect(blocksOn(s, lower), [(6, 7)]);
    expect(blocksOn(s, upper), [(6, 9)]);
    expect(cellsSelected(s), (4, 9));
    expect(s.frameRangeSelection.value!.spanLayerIds, rows);
  });

  test('with nothing selected a shove selects nothing', () {
    final (:s, :row) = blockOnFourSelected([0, 4]);
    s.clearTimelineSelections();
    s.selectFrameIndex(4);

    shoveOf(s).pushFrames(1);

    expect(blocksOn(s, row), [(0, 1), (5, 6)]);
    expect(s.frameRangeSelection.value, isNull);
  });
}
