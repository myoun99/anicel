import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowSubject;

/// 🗣️F-563 (유저 2026-11-04): 「레이어 여러개 선택하고 폴더생성누르면
/// 선택한 레이어들 폴더안에 들어가는식으로」.
///
/// Add Layer's folder holds every row the row selection holds — as a drag
/// of those rows let go ON an empty folder puts them, which is the one law
/// of what goes in a folder — and none when the selection holds none.
/// One undo step.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  List<Layer> stackOf(EditorSessionManager s) => s.requireActiveCut.layers;

  /// [count] new drawing rows over the one [s] stands on, bottom → top.
  List<LayerId> addRows(EditorSessionManager s, int count) => [
    for (var i = 0; i < count; i += 1) _added(s, LayerKind.animation),
  ];

  void select(EditorSessionManager s, Iterable<LayerId> rows) =>
      s.rowSelection.value = [for (final id in rows) LayerRowAddress(id)];

  LayerId addFolder(EditorSessionManager s) =>
      _added(s, LayerKind.folder);

  /// The stack as structure: each row's name and its folder's, bottom →
  /// top — names, so two sessions' stacks compare.
  List<String> shapeOf(EditorSessionManager s) {
    final stack = stackOf(s);
    return [
      for (final layer in stack)
        '${layer.name} in ${switch (layer.folderId) {
          final id? => stack.byId(id)?.name,
          null => null,
        }}',
    ];
  }

  test('🎯the rows selected go in as a drag of them let go on an empty '
      'folder puts them', () {
    for (final picked in [
      [1, 2],
      [0, 2],
      [2],
      [0, 1, 2],
    ]) {
      final made = session();
      final rows = addRows(made, 3);
      made.selectLayer(rows[picked.last]);
      select(made, [for (final i in picked) rows[i]]);
      final folder = addFolder(made);

      final dragged = session();
      final same = addRows(dragged, 3);
      dragged.selectLayer(same[picked.last]);
      final empty = addFolder(dragged);
      expect(
        stackOf(dragged).where((layer) => layer.folderId == empty),
        isEmpty,
        reason: '⛔전제: nothing selected, nothing held',
      );
      select(dragged, [for (final i in picked) same[i]]);
      _dropOn(dragged, same[picked.first], empty);

      expect(
        shapeOf(made),
        shapeOf(dragged),
        reason: 'picked $picked',
      );
      expect(
        [for (final i in picked) stackOf(made).byId(rows[i])!.folderId],
        everyElement(folder),
        reason: 'picked $picked',
      );
      expect(folderStructureProblem(stackOf(made)), isNull);
      expect(made.activeLayerId, folder, reason: 'you stand on what you made');
    }
  });

  test('it is ONE undo — the folder and what it holds go and come back '
      'together', () {
    final s = session();
    final rows = addRows(s, 2);
    final before = shapeOf(s);
    select(s, rows);
    final folder = addFolder(s);
    final after = shapeOf(s);

    s.undo();
    expect(shapeOf(s), before);

    s.redo();
    expect(shapeOf(s), after);
    expect(stackOf(s).byId(rows.first)!.folderId, folder);
  });

  test('nothing selected — the folder is born holding nothing, where every '
      'new row is', () {
    final s = session();
    final rows = addRows(s, 2);
    s.rowSelection.value = const [];
    final folder = addFolder(s);

    final stack = stackOf(s);
    expect(stack.where((layer) => layer.folderId == folder), isEmpty);
    expect(stack.indexWhere((layer) => layer.id == folder),
        stack.indexWhere((layer) => layer.id == rows.last) + 1);
  });

  test('rows selected inside a folder go into a new folder inside it', () {
    final s = session();
    final rows = addRows(s, 2);
    select(s, rows);
    final outer = addFolder(s);
    select(s, [rows.last]);

    final inner = addFolder(s);

    final stack = stackOf(s);
    expect(stack.byId(inner)!.folderId, outer);
    expect(stack.byId(rows.last)!.folderId, inner);
    expect(stack.byId(rows.first)!.folderId, outer);
    expect(folderStructureProblem(stack), isNull);
  });

  test('a selection of rows the cut does not hold — a track\'s — holds '
      'nothing', () {
    final s = session();
    addRows(s, 1);
    final se = s.layerStack.addSeLane();
    select(s, [se]);

    final folder = addFolder(s);

    expect(
      stackOf(s).where((layer) => layer.folderId == folder),
      isEmpty,
    );
    expect(folderStructureProblem(stackOf(s)), isNull);
  });
}

/// The row [s] made with Add Layer's [kind], stood on.
LayerId _added(EditorSessionManager s, LayerKind kind) {
  s.layerStack.addLayerOfKind(kind);
  return s.activeLayerId!;
}

/// One whole drag of [moving]'s row — the selection it is in with it —
/// let go ON [target]'s.
void _dropOn(EditorSessionManager s, LayerId moving, LayerId target) {
  final drag = s.layerRowDragVerbs;
  final layers = s.layers;
  drag.beginLayerRowDrag(LayerRowSubject(moving));
  drag.updateLayerRowDropOnRow(
    layers,
    layers.indexWhere((layer) => layer.id == target),
    target,
  );
  drag.endLayerRowDrag();
}
