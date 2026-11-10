import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/folders_and_attachments.dart';

/// 🗣️F-574 — 어태치 해제 LETS GO EVERY SELECTED ROW IT CAN.
///
/// 유저 2026-11-08: 「레이어 복수선택후 어태치해제 버튼하면 복수 레이어
/// 어태치해제되도록. 이런 로직은 모두 복수선택이면 복수선택에 적용이
/// 기본임. 물론 선택한 레이어중 가능한레이어만」. The rows are the rename's —
/// the selected rows it can let go, else the one stood on — by one code, as
/// ONE undo step.
///
/// The collaborator is held BY ITS OWN TYPE so the mutation runner names
/// this file as its witness (it picks witnesses by import).
void main() {
  FoldersAndAttachments foldersOf(EditorSessionManager s) => s.folders;

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  List<Layer> rows(EditorSessionManager s) => s.requireActiveCut.layers;

  int at(EditorSessionManager s, LayerId id) =>
      rows(s).indexWhere((layer) => layer.id == id);

  LayerId? riding(EditorSessionManager s, LayerId id) =>
      rows(s)[at(s, id)].attachedToLayerId;

  /// A base with two riders above it — [near] the first, [far] the one
  /// added over it — and one below.
  ({LayerId base, LayerId near, LayerId far, LayerId below}) aGroup(
    EditorSessionManager s,
  ) {
    final base = s.activeLayer!.id;
    s.createDrawingAtCurrentFrame();
    foldersOf(s).addAttachedLayer(AttachedPlacement.above);
    final near = s.activeLayer!.id;
    foldersOf(s).addAttachedLayer(AttachedPlacement.above);
    final far = s.activeLayer!.id;
    s.selectLayer(base);
    foldersOf(s).addAttachedLayer(AttachedPlacement.below);
    final below = s.activeLayer!.id;
    for (final rider in [near, far, below]) {
      expect(riding(s, rider), base, reason: '⛔전제');
    }
    expect(
      (at(s, far) - at(s, base)).abs(),
      greaterThan((at(s, near) - at(s, base)).abs()),
      reason: '⛔전제: the second rider went over the first',
    );
    return (base: base, near: near, far: far, below: below);
  }

  void select(EditorSessionManager s, List<LayerId> ids) {
    s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(ids.first));
    s.rowSelectionVerbs.rowSelection.value = [
      for (final id in ids) LayerRowAddress(id),
    ];
  }

  test('every selected rider lets go, the base among them passed by, as ONE '
      'undo step — and the riders keep the order they stood in', () {
    final s = session();
    final g = aGroup(s);
    // The near rider first: let go first, it would step out past the far
    // one and the two would trade places.
    select(s, [g.near, g.base, g.far, g.below]);
    final farOverNear = at(s, g.far) > at(s, g.near);
    final entries = s.historyManager.undoCount;
    expect(foldersOf(s).canDetachRows, isTrue);

    foldersOf(s).detachRows();

    for (final rider in [g.near, g.far, g.below]) {
      expect(riding(s, rider), isNull, reason: '$rider');
    }
    expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
    expect(at(s, g.far) > at(s, g.near), farOverNear, reason: 'no trade');
    expect(folderStructureProblem(rows(s)), isNull);

    s.undo();
    for (final rider in [g.near, g.far, g.below]) {
      expect(riding(s, rider), g.base, reason: 'one undo puts back $rider');
    }
  });

  test('with no selection it is the row stood on alone, by the same code', () {
    final s = session();
    final g = aGroup(s);
    s.clearRowSelection();
    s.selectLayer(g.near);

    foldersOf(s).detachRows();

    expect(riding(s, g.near), isNull);
    expect(riding(s, g.far), g.base, reason: 'nobody named it');
    expect(riding(s, g.below), g.base);
    expect(s.activeLayerId, g.near, reason: 'standing where you stood');
  });

  test('⛔a selection of rows none of which rides holds nothing to let '
      'go — the button dims', () {
    final s = session();
    final g = aGroup(s);
    s.selectLayer(g.base);
    select(s, [g.base]);
    expect(foldersOf(s).canDetachRows, isFalse);
  });
}
