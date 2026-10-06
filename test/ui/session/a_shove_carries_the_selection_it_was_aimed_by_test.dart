import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/block_shift.dart';

/// 🚨F-264 (유저 2026-10-02): 「타임라인 버튼 밀기/당기기 작동시 선택범위로
/// 여러행선택한거라던가 블록 선택범위 풀리는데 안풀리도록」.
///
/// A shove's scope is the selection — its rows, anchored at its start — so
/// the selection is what the NEXT press is aimed by. The shove ended with
/// the cut commands' tidy-up, which drops the frame selection: the second
/// press shoved from the playhead instead. It is carried with the blocks
/// now; left on the cells it covered, a second pull would find the block it
/// had just moved standing before its anchor and pass it by.
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

  /// One row holding a block at 0 and another at 4, the second selected.
  ({EditorSessionManager s, LayerId row}) secondBlockSelected() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final row = s.activeLayer!.id;
    for (final frame in [0, 4]) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
    }
    s.updateFrameRangeSelectionDrag(layerId: row, anchorIndex: 4, headIndex: 4);
    expect(cellsSelected(s), (4, 5), reason: '⛔전제');
    return (s: s, row: row);
  }

  test('pushed, the selected block is still what is selected — where it '
      'went', () {
    final (:s, :row) = secondBlockSelected();

    shoveOf(s).pushFrames(2);

    expect(blocksOn(s, row), [(0, 1), (6, 7)]);
    expect(cellsSelected(s), (6, 7), reason: '「안풀리도록」');
    expect(s.frameRangeSelection.value!.spanLayerIds, [row]);
  });

  test('pulled twice, it is the same block both times — the anchor goes '
      'with it', () {
    final (:s, :row) = secondBlockSelected();

    shoveOf(s).pullFrames(1);
    shoveOf(s).pullFrames(1);

    expect(blocksOn(s, row), [(0, 1), (2, 3)]);
    expect(cellsSelected(s), (2, 3));
    // …and stops where it touches, selection and all.
    shoveOf(s).pullFrames(9);
    expect(blocksOn(s, row), [(0, 1), (1, 2)]);
    expect(cellsSelected(s), (1, 2));
  });

  test('a band over several rows keeps every row', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final lower = s.activeLayer!.id;
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame();
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final upper = s.activeLayer!.id;
    s.selectFrameIndex(4);
    s.createDrawingAtCurrentFrame();
    s.updateFrameRangeSelectionDrag(
      layerId: lower,
      anchorIndex: 4,
      headIndex: 4,
      headLayerId: upper,
    );
    final rows = s.frameRangeSelection.value!.spanLayerIds;
    expect(rows, unorderedEquals([lower, upper]), reason: '⛔전제');

    shoveOf(s).pushFrames(1);
    shoveOf(s).pushFrames(1);

    expect(blocksOn(s, lower), [(6, 7)]);
    expect(blocksOn(s, upper), [(6, 7)]);
    expect(cellsSelected(s), (6, 7));
    expect(s.frameRangeSelection.value!.spanLayerIds, rows);
  });

  test('with nothing selected a shove selects nothing', () {
    final (:s, :row) = secondBlockSelected();
    s.clearAllSelections();
    s.selectFrameIndex(4);

    shoveOf(s).pushFrames(1);

    expect(blocksOn(s, row), [(0, 1), (5, 6)]);
    expect(s.frameRangeSelection.value, isNull);
  });
}
