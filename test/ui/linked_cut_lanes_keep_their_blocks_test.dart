import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

typedef _CelInBothCuts = ({
  CutId cut1,
  LayerId row1,
  CutId cut2,
  LayerId row2,
  FrameId cel,
});

/// 🚨F-136 (유저 2026-09-14): 「컷2에서 A레이어의 프레임 1을 지웠다고
/// 컷1에서도 삭제되거든? … 같은 컷 내에서 프레임1이 두개있을때, 한 프레임
/// 1을 삭제한다고 다른게 삭제되지않잖아. 똑같은거니까 법 통일해서 해결」 —
/// 「링크컷으로 연결되있을때 얘기야」.
///
/// A 겸용 cut's rows share ONE cel bank and keep their own lanes. A lane
/// edit that stops exposing a cel may take the cel out of the bank only
/// when NO lane of that bank still exposes it — the question the second
/// 「1」 on the same row already answers, asked of every lane.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  Layer rowIn(CutId cutId, LayerId layerId) => session.activeTrack.cuts
      .firstWhere((cut) => cut.id == cutId)
      .layers
      .firstWhere((layer) => layer.id == layerId);

  /// The row of ([of], [row])'s link group that lives in [cutId] and is not
  /// [row] itself.
  LayerId memberIn(CutId cutId, {required CutId of, required LayerId row}) =>
      session.repository
          .requireProject()
          .linkRegistry
          .groupOf(cutId: of, layerId: row)!
          .members
          .firstWhere(
            (member) => member.cutId == cutId && member.layerId != row,
          )
          .layerId;

  /// The user's state: 「A1」 — a cel named 「1」 drawn at frame 0 of cut 1,
  /// the 겸용 cut made from cut 1, and a drawing at frame 0 of the linked
  /// row named 「1」 too, which joins it to the SAME cel. [secondRow] adds
  /// an empty row to cut 1 first, so the linked cut has a row to move onto.
  _CelInBothCuts celInBothCuts({bool secondRow = false}) {
    final cut1 = session.requireActiveCut.id;
    final row1 = session.activeLayer!.id;
    if (secondRow) {
      session.layerStack.addLayer();
      session.selectLayer(row1);
    }
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    expect(
      session.frameVerbs.renameSelectedFrame('1'),
      isNull,
      reason: 'LIVENESS — cut 1\'s cel takes the name 「1」',
    );
    final cel = rowIn(cut1, row1).timeline[0]!.frameId!;

    session.cutVerbs.createLinkedCutFromActiveCut();
    final cut2 = session.requireActiveCut.id;
    expect(cut2, isNot(cut1), reason: 'LIVENESS — the 겸용 cut is active');
    final row2 = memberIn(cut2, of: cut1, row: row1);
    session.selectLayer(row2);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    final conflict = session.frameVerbs.renameSelectedFrame('1');
    expect(conflict, cel, reason: 'LIVENESS — the name offers the join');
    session.frameVerbs.linkSelectedFrame(conflict!);
    expect(
      rowIn(cut2, row2).timeline[0]?.frameId,
      cel,
      reason: 'LIVENESS — the linked row exposes the same cel',
    );
    return (cut1: cut1, row1: row1, cut2: cut2, row2: row2, cel: cel);
  }

  void expectKept(
    _CelInBothCuts pair, {
    required CutId cutId,
    required LayerId rowId,
    required String when,
  }) {
    expect(
      rowIn(cutId, rowId).timeline[0]?.frameId,
      pair.cel,
      reason: '⛔$when: a block in ANOTHER cut is not this edit\'s to take',
    );
    for (final (cut, row) in [(pair.cut1, pair.row1), (pair.cut2, pair.row2)]) {
      expect(
        rowIn(cut, row).frameById(pair.cel),
        isNotNull,
        reason: '⛔$when: a cel some lane still exposes stays in the bank',
      );
    }
  }

  test('deleting the block in the 겸용 cut leaves cut 1\'s block', () {
    final pair = celInBothCuts();

    session.cells.deleteCellAtCurrentFrame();

    expect(
      rowIn(pair.cut2, pair.row2).timeline,
      isEmpty,
      reason: 'LIVENESS — the delete happened',
    );
    expectKept(pair, cutId: pair.cut1, rowId: pair.row1, when: 'delete');
  });

  test('and the other way round: deleting in cut 1 leaves the 겸용 cut\'s '
      'block', () {
    final pair = celInBothCuts();
    session.selectCut(pair.cut1);
    session.selectLayer(pair.row1);
    session.selectFrameIndex(0);

    session.cells.deleteCellAtCurrentFrame();

    expect(
      rowIn(pair.cut1, pair.row1).timeline,
      isEmpty,
      reason: 'LIVENESS — the delete happened',
    );
    expectKept(pair, cutId: pair.cut2, rowId: pair.row2, when: 'delete');
  });

  test('a 잘라내기 in the 겸용 cut asks the same question', () {
    final pair = celInBothCuts();

    session.clipboard.cutRunAtCurrentFrame();

    expect(
      rowIn(pair.cut2, pair.row2).timeline,
      isEmpty,
      reason: 'LIVENESS — the cut lifted the block',
    );
    expectKept(pair, cutId: pair.cut1, rowId: pair.row1, when: '잘라내기');
  });

  test('joining a cel by name in the 겸용 cut relinks ITS lane and leaves '
      'cut 1\'s block on the cel it showed', () {
    final pair = celInBothCuts();
    session.selectFrameIndex(1);
    session.createDrawingAtCurrentFrame();
    expect(
      session.frameVerbs.renameSelectedFrame('named'),
      isNull,
      reason: 'LIVENESS — a free name renames',
    );
    final named = rowIn(pair.cut2, pair.row2).timeline[1]!.frameId!;
    session.selectFrameIndex(0);

    final conflict = session.frameVerbs.renameSelectedFrame('named');
    expect(conflict, named, reason: 'LIVENESS — the name offers the join');
    session.frameVerbs.linkSelectedFrame(conflict!);

    expect(
      rowIn(pair.cut2, pair.row2).timeline[0]?.frameId,
      named,
      reason: 'LIVENESS — the join relinked this lane',
    );
    expectKept(pair, cutId: pair.cut1, rowId: pair.row1, when: 'join');
  });

  /// The linked cut's OTHER drawing row, for a move to land on — the member
  /// of cut 1's second drawing row ([celInBothCuts] with `secondRow`).
  LayerId otherRowOf(_CelInBothCuts pair) {
    final kind = rowIn(pair.cut1, pair.row1).kind;
    final otherRow1 = session.activeTrack.cuts
        .firstWhere((cut) => cut.id == pair.cut1)
        .layers
        .firstWhere((layer) => layer.id != pair.row1 && layer.kind == kind)
        .id;
    return memberIn(pair.cut2, of: pair.cut1, row: otherRow1);
  }

  void expectRefused(_CelInBothCuts pair, {required String when}) {
    expectKept(pair, cutId: pair.cut1, rowId: pair.row1, when: when);
    expect(
      rowIn(pair.cut2, pair.row2).timeline[0]?.frameId,
      pair.cel,
      reason: 'the move is refused, the same way a cel another block of '
          'the SAME row exposes stays put',
    );
  }

  test('moving the block onto another row does not carry off a cel another '
      'cut still shows', () {
    final pair = celInBothCuts(secondRow: true);
    final otherRow2 = otherRowOf(pair);
    session.updateFrameRangeSelectionDrag(
      layerId: pair.row2,
      anchorIndex: 0,
      headIndex: 0,
    );

    expect(session.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    session.rangeMove.updateFrameRangeMoveDrag(
      frameDelta: 0,
      targetLayerId: otherRow2,
    );
    session.rangeMove.endFrameRangeMoveDrag();

    expectRefused(pair, when: 'row move');
  });

  test('and the grip drag of that block asks the same bank', () {
    final pair = celInBothCuts(secondRow: true);
    final otherRow2 = otherRowOf(pair);

    expect(
      session.drawingBlockMove.beginDrawingBlockMoveDrag(
        layerId: pair.row2,
        blockStartIndex: 0,
      ),
      isTrue,
    );
    session.drawingBlockMove.updateDrawingBlockMoveDrag(
      frameDelta: 0,
      targetLayerId: otherRow2,
    );
    session.drawingBlockMove.endDrawingBlockMoveDrag();

    expectRefused(pair, when: 'grip drag');
  });

  test('a MULTI-ROW move asks every carried row\'s bank', () {
    final cut1 = session.requireActiveCut.id;
    final rowA1 = session.activeLayer!.id;
    session.layerStack.addLayer();
    final rowB1 = session.activeLayer!.id;
    session.layerStack.addLayer(); // the empty row the shift lands on

    FrameId drawNamed(LayerId row, String name) {
      session.selectLayer(row);
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      expect(session.frameVerbs.renameSelectedFrame(name), isNull);
      return rowIn(cut1, row).timeline[0]!.frameId!;
    }

    final celA = drawNamed(rowA1, '1');
    final celB = drawNamed(rowB1, '2');
    session.cutVerbs.createLinkedCutFromActiveCut();
    final cut2 = session.requireActiveCut.id;
    final rowA2 = memberIn(cut2, of: cut1, row: rowA1);
    final rowB2 = memberIn(cut2, of: cut1, row: rowB1);
    for (final (row, name, cel) in [(rowA2, '1', celA), (rowB2, '2', celB)]) {
      session.selectLayer(row);
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      session.frameVerbs.linkSelectedFrame(
        session.frameVerbs.renameSelectedFrame(name)!,
      );
      expect(rowIn(cut2, row).timeline[0]?.frameId, cel, reason: 'LIVENESS');
    }
    session.selectLayer(rowA2);
    session.updateFrameRangeSelectionDrag(
      layerId: rowA2,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: rowB2,
    );
    expect(session.frameRangeSelection.value!.spanLayerIds, [rowA2, rowB2]);

    expect(session.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    session.rangeMove.updateFrameRangeMoveDrag(
      frameDelta: 0,
      targetLayerId: rowB2,
    );
    session.rangeMove.endFrameRangeMoveDrag();

    expect(
      rowIn(cut1, rowA1).timeline[0]?.frameId,
      celA,
      reason: '⛔a multi-row shift took a cel cut 1 still shows',
    );
    expect(rowIn(cut1, rowB1).timeline[0]?.frameId, celB);
    expect(
      rowIn(cut2, rowA2).timeline[0]?.frameId,
      celA,
      reason: 'the whole rigid shift is refused',
    );
  });

  group('the law this unifies — two exposures inside ONE bank', () {
    test('two blocks of one cel on one row: deleting one keeps the other', () {
      final cut = session.requireActiveCut.id;
      final row = session.activeLayer!.id;
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      final cel = rowIn(cut, row).timeline[0]!.frameId!;
      session.clipboard.copyFrameAtCurrentFrame();
      session.clipboard.pasteLinkedFrameAtCurrentFrame();
      expect(
        rowIn(cut, row).timeline[1]?.frameId,
        cel,
        reason: 'LIVENESS — the paste pushed the first block to frame 1',
      );

      session.selectFrameIndex(0);
      session.cells.deleteCellAtCurrentFrame();

      expect(rowIn(cut, row).timeline[1]?.frameId, cel);
      expect(rowIn(cut, row).frameById(cel), isNotNull);
    });

    test('a link-duplicated row in the SAME cut: deleting on one row keeps '
        'the other row\'s block', () {
      final cut = session.requireActiveCut.id;
      final row = session.activeLayer!.id;
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      final cel = rowIn(cut, row).timeline[0]!.frameId!;
      session.clipboard.copyFrameAtCurrentFrame();
      session.layerVerbs.linkDuplicateActiveLayer();
      final twin = memberIn(cut, of: cut, row: row);
      if (rowIn(cut, twin).timeline[0]?.frameId != cel) {
        session.selectLayer(twin);
        session.selectFrameIndex(0);
        session.clipboard.pasteLinkedFrameAtCurrentFrame();
      }
      expect(
        rowIn(cut, twin).timeline[0]?.frameId,
        cel,
        reason: 'LIVENESS — the twin row exposes the same cel',
      );

      session.selectLayer(row);
      session.selectFrameIndex(0);
      session.cells.deleteCellAtCurrentFrame();

      expect(
        rowIn(cut, row).timeline[0],
        isNull,
        reason: 'LIVENESS — the delete happened',
      );
      expect(rowIn(cut, twin).timeline[0]?.frameId, cel);
      expect(rowIn(cut, twin).frameById(cel), isNotNull);
    });
  });
}
