import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/services/project_lookup.dart' show requireLayer;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/block_naming.dart';

/// 🗣️I-18 — 자동 이름 지정, said of the TIMELINE (유저): 「대상은 선택된
/// 블록들(컷이나 프레임)이 있으면 선택한 대상만. 없으면 현재 인덱스에 위치한
/// 블록부터 해당 행에서 마지막 존재하는 블록까지」, numbered by first
/// appearance (I-18-Q1 「그림마다 번호 — 다시 나오는 블록은 같은 번호」).
///
/// The collaborator is held BY ITS OWN TYPE so the mutation runner names this
/// file as its witness (it picks witnesses by import).
void main() {
  BlockNaming namingOf(EditorSessionManager s) => s.blockNaming;

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  Layer rowOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((layer) => layer.id == id);

  /// What each of [row]'s cells [0, count) reads.
  List<String?> reads(EditorSessionManager s, LayerId row, int count) => [
    for (var index = 0; index < count; index += 1)
      s.frameVerbs.frameNameForLayer(rowOf(s, row), index),
  ];

  /// A drawing named [name] at [index] on the active row.
  FrameId drawn(EditorSessionManager s, int index, String name) {
    s.selectFrameIndex(index);
    s.createDrawingAtCurrentFrame();
    expect(s.frameVerbs.renameSelectedFrame(name), isNull, reason: '⛔전제');
    return s.selectedFrame!.id;
  }

  /// The drawing at [from] shown again at [to] — a LINK paste (Ctrl+B).
  void linkedAgain(EditorSessionManager s, int from, int to) {
    s.selectFrameIndex(from);
    s.copyFrameAtCurrentFrame();
    s.selectFrameIndex(to);
    s.pasteLinkedFrameAtCurrentFrame();
  }

  /// The active row reading 1 2 1 3 on cells 0..3: drawings A B A C.
  LayerId oneTwoOneThree(EditorSessionManager s) {
    drawn(s, 0, '1');
    drawn(s, 1, '2');
    linkedAgain(s, 0, 2);
    drawn(s, 3, '3');
    final row = s.activeLayerId!;
    expect(reads(s, row, 4), ['1', '2', '1', '3'], reason: '⛔전제');
    return row;
  }

  /// Plans [from] for the timeline's targets and writes it, as the
  /// window's Apply does when no name is taken outside.
  void press(EditorSessionManager s, int from) {
    final naming = namingOf(s);
    final plan = naming.plan(naming.timelineTargets!, from: from);
    expect(plan.hasJoins, isFalse, reason: '⛔전제: nothing to ask');
    naming.apply(plan);
  }

  test('a drawing shown again reads the number it took first: 1 2 1 3 from '
      '5 reads 5 6 5 7, and ONE undo gives it back', () {
    final s = session();
    final row = oneTwoOneThree(s);
    s.selectFrameIndex(0);
    final entries = s.historyManager.undoCount;

    press(s, 5);

    expect(reads(s, row, 4), ['5', '6', '5', '7']);
    expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
    s.undo();
    expect(reads(s, row, 4), ['1', '2', '1', '3']);
  });

  test('standing on the repeat: from that block to the row\'s last — the '
      'drawing it shows reads its number everywhere, the one before it is '
      'left alone', () {
    final s = session();
    final row = oneTwoOneThree(s);
    s.selectFrameIndex(2);

    press(s, 5);

    expect(reads(s, row, 4), ['5', '2', '5', '6']);
  });

  test('a band names ONLY its blocks — a drawing it numbers reads the '
      'number wherever it is shown', () {
    final s = session();
    final row = oneTwoOneThree(s);
    s.selectFrameIndex(0);
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: row,
      startIndex: 1,
      endIndexExclusive: 3,
    );

    press(s, 5);

    expect(reads(s, row, 4), ['6', '5', '6', '3']);
  });

  test('a band over several rows numbers each row from the start', () {
    final s = session();
    final first = s.activeLayerId!;
    drawn(s, 0, 'a');
    drawn(s, 1, 'b');
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final second = s.activeLayerId!;
    drawn(s, 0, 'c');
    drawn(s, 1, 'd');
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: first,
      startIndex: 0,
      endIndexExclusive: 2,
      layerIds: [first, second],
    );

    press(s, 5);

    expect(reads(s, first, 2), ['5', '6']);
    expect(reads(s, second, 2), ['5', '6']);
  });

  test('⛔an empty cell and a GHOST are no block (targets-Q2 「블록으로 치지 '
      '않는다」): the button dims and nothing is written', () {
    final s = session();
    final row = s.activeLayerId!;
    drawn(s, 0, '1');
    s.rangeMove.setRunEdgeBehavior(
      layerId: row,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );
    expect(
      coveringDrawingBlockAt(rowOf(s, row).timeline, 1)?.entry.ghost,
      isTrue,
      reason: '⛔전제: the hold drew a ghost of the drawing at 1',
    );

    s.selectFrameIndex(1);
    expect(namingOf(s).timelineTargets, isNull, reason: 'a ghost');
    s.selectFrameIndex(0);
    expect(namingOf(s).timelineTargets, isNotNull, reason: 'the block');

    s.layerStack.addLayerOfKind(LayerKind.animation);
    s.selectFrameIndex(0);
    expect(namingOf(s).timelineTargets, isNull, reason: 'an empty cell');
  });

  test('⛔a lane row, a lane band and a band over empty cells each claim the '
      'press and hold nothing to number', () {
    final s = session();
    final row = oneTwoOneThree(s);
    s.selectFrameIndex(0);
    expect(namingOf(s).timelineTargets, isNotNull, reason: '⛔전제');

    s.standOnRow(LaneRowAddress(row, 'position'));
    expect(namingOf(s).timelineTargets, isNull, reason: 'a lane row');

    s.standOnRow(LayerRowAddress(row));
    s.updateLaneRangeSelectionDrag(
      layerId: row,
      laneId: 'position',
      anchorIndex: 0,
      headIndex: 2,
      spanLaneIds: const [],
    );
    expect(namingOf(s).timelineTargets, isNull, reason: 'a lane band');

    s.laneRangeSelection.value = null;
    s.standOnRow(LayerRowAddress(row));
    expect(
      namingOf(s).timelineTargets,
      isNotNull,
      reason: '⛔전제: back on the row, nothing claims the press',
    );
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: row,
      startIndex: 20,
      endIndexExclusive: 22,
    );
    expect(namingOf(s).timelineTargets, isNull, reason: 'an empty band');
  });

  test('targets-Q1: a band across the SE, direction and image rows numbers '
      'the IMAGE row and leaves the SE and direction rows alone', () {
    final s = session();
    final drawing = s.activeLayerId!;
    drawn(s, 0, 'x');
    s.layerStack.addLayerOfKind(LayerKind.image);
    final image = s.activeLayerId!;
    s.layerStack.addLayerOfKind(LayerKind.se);
    final se = s.activeLayerId!;
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: 'line', lengthFrames: 1);
    s.layerStack.addLayerOfKind(LayerKind.instruction);
    final direction = s.activeLayerId!;
    s.updateFrameRangeSelectionDrag(
      layerId: direction,
      anchorIndex: 0,
      headIndex: 1,
    );
    expect(s.cellInstances.createInstancesForSelection(), isTrue);
    for (final id in [image, se, direction]) {
      expect(
        rowOf(s, id).timeline[0]?.isDrawing,
        isTrue,
        reason: '⛔전제: ${rowOf(s, id).kind.name} has a block at 0',
      );
    }
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: drawing,
      startIndex: 0,
      endIndexExclusive: 2,
      layerIds: [drawing, image, se, direction],
    );

    final targets = namingOf(s).timelineTargets! as AutoNameFrames;
    expect(
      [for (final row in targets.rows) row.layerId],
      unorderedEquals([drawing, image]),
    );

    press(s, 5);

    expect(s.frameVerbs.frameNameForLayer(rowOf(s, image), 0), '5');
    expect(s.frameVerbs.frameNameForLayer(rowOf(s, drawing), 0), '5');
    expect(
      s.frameVerbs.frameNameForLayer(rowOf(s, se), 0),
      'line',
      reason: 'an SE entry\'s name is its dialogue',
    );
  });

  test('a name held OUTSIDE the press asks first: the notice lists every '
      'drawing a join discards, and joining gives 1 2 1 2 as ONE step', () {
    final s = session();
    final row = s.activeLayerId!;
    final one = drawn(s, 0, '1');
    final two = drawn(s, 1, '2');
    final three = drawn(s, 2, '3');
    final four = drawn(s, 3, '4');
    s.selectFrameIndex(2);
    final naming = namingOf(s);

    final plan = naming.plan(naming.timelineTargets!, from: 1);

    expect(plan.hasJoins, isTrue);
    expect(plan.joinLines, hasLength(2), reason: 'both collisions listed');
    expect(plan.rows.single.joins, {three: one, four: two});
    expect(reads(s, row, 4), ['1', '2', '3', '4'], reason: 'nothing written');

    final entries = s.historyManager.undoCount;
    naming.apply(plan);

    expect(reads(s, row, 4), ['1', '2', '1', '2']);
    expect(
      [for (final frame in rowOf(s, row).frames) frame.id],
      [one, two],
      reason: 'the joined drawings leave the bank — nothing shows them',
    );
    expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
    s.undo();
    expect(reads(s, row, 4), ['1', '2', '3', '4']);
  });

  test('a row linked with another cut (겸용): the other cut\'s bank takes the '
      'names, and ONE undo gives both back', () {
    final s = session();
    final row = s.activeLayerId!;
    final first = s.activeCutId!;
    drawn(s, 0, '1');
    drawn(s, 1, '2');
    s.cutVerbs.createLinkedCutFromActiveCut();
    final linkedCut = s.activeCutId!;
    final partner = s.repository
        .requireProject()
        .linkRegistry
        .groupOf(cutId: first, layerId: row)!
        .members
        .firstWhere((member) => member.cutId == linkedCut)
        .layerId;
    s.selectCut(first);
    s.selectLayer(row);
    s.selectFrameIndex(0);

    press(s, 5);

    List<String?> partnerNames() => [
      for (final frame in requireLayer(
        s.repository.requireProject(),
        cutId: linkedCut,
        layerId: partner,
      ).frames)
        frame.name,
    ];
    expect(partnerNames(), ['5', '6']);
    s.undo();
    expect(partnerNames(), ['1', '2']);
    expect(reads(s, row, 2), ['1', '2']);
  });

  test('two rows sharing ONE bank in a band: a drawing takes one number, '
      'however many rows show it', () {
    final s = session();
    final original = s.activeLayerId!;
    final a = drawn(s, 0, 'a');
    final b = drawn(s, 1, 'b');
    s.layerVerbs.linkDuplicateActiveLayer();
    final copy = s.layers
        .firstWhere(
          (layer) =>
              layer.id != original && s.layerVerbs.isLayerLinked(layer.id),
        )
        .id;
    expect(rowOf(s, copy).timeline[0]?.frameId, a, reason: '⛔전제');
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: original,
      startIndex: 0,
      endIndexExclusive: 2,
      layerIds: [original, copy],
    );

    press(s, 5);

    expect(reads(s, original, 2), ['5', '6']);
    expect(reads(s, copy, 2), ['5', '6']);
    expect(
      [for (final frame in rowOf(s, original).frames) frame.id],
      [a, b],
      reason: 'numbered, not joined — the bank keeps both drawings',
    );
  });

  test('targets-Q3: rows selected in the rail, no band — each from the block '
      'at the playhead to its own last', () {
    final s = session();
    final first = s.activeLayerId!;
    drawn(s, 0, 'a');
    drawn(s, 1, 'b');
    drawn(s, 2, 'c');
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final second = s.activeLayerId!;
    drawn(s, 0, 'd');
    drawn(s, 1, 'e');
    s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(first));
    s.rowSelectionVerbs.rowSelection.value = [
      LayerRowAddress(first),
      LayerRowAddress(second),
    ];
    s.selectFrameIndex(1);
    expect(
      namingOf(s).timelineTargets,
      isA<AutoNameFrames>().having(
        (targets) => targets.rows.length,
        'rows',
        2,
      ),
      reason: '⛔전제: the rows rung, both rows',
    );

    press(s, 5);

    expect(reads(s, first, 3), ['a', '5', '6']);
    expect(reads(s, second, 2), ['d', '5']);
  });
}
