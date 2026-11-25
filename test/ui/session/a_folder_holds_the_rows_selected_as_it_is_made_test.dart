import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_sections.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart'
    show PointerInRow, resolveLayerDrop;
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

  /// [stack] as structure: each row's name and its folder's, bottom → top
  /// — names, so two sessions' stacks compare.
  List<String> shapeIn(List<Layer> stack) => [
    for (final layer in stack)
      '${layer.name} in ${switch (layer.folderId) {
        final id? => stack.byId(id)?.name,
        null => null,
      }}',
  ];

  List<String> shapeOf(EditorSessionManager s) => shapeIn(stackOf(s));

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

  test('🎯made in a 겸용 cut, the folder holds the same rows in its sibling '
      '— as the same drag does', () {
    /// A session standing on a cut that has a 겸용, with [count] rows
    /// added there — and so in its sibling.
    ({EditorSessionManager s, List<LayerId> rows}) linked(int count) {
      final s = session();
      final source = s.requireActiveCut.id;
      s.cutVerbs.createLinkedCutFromActiveCut();
      s.selectCut(source);
      return (s: s, rows: addRows(s, count));
    }

    List<List<String>> everyCut(EditorSessionManager s) => [
      for (final cut in s.activeTrack.cuts) shapeIn(cut.layers),
    ];

    final made = linked(3);
    made.s.selectLayer(made.rows[2]);
    select(made.s, [made.rows[0], made.rows[2]]);
    final folder = addFolder(made.s);

    final dragged = linked(3);
    dragged.s.selectLayer(dragged.rows[2]);
    final empty = addFolder(dragged.s);
    select(dragged.s, [dragged.rows[0], dragged.rows[2]]);
    _dropOn(dragged.s, dragged.rows[0], empty);

    expect(everyCut(made.s), everyCut(dragged.s));
    final sibling = made.s.activeTrack.cuts.singleWhere(
      (cut) => cut.id != made.s.requireActiveCut.id,
    );
    expect(
      shapeIn(sibling.layers),
      shapeOf(made.s),
      reason: 'the 겸용 wears it',
    );
    expect(stackOf(made.s).byId(made.rows[0])!.folderId, folder);
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

  // 🗣️검증 2026-11-23 (F-596 ④, card
  // a-selection-across-sections-makes-an-empty-folder): rows picked from
  // the direction row down to a drawing row made a folder holding NOTHING
  // — the drawing row neither. 🗣️-Q1 (유저 2026-11-23): 「줄마다 제 칸을
  // 지킨다 — 디렉션 · 카메라 줄은 그림 폴더에 안 든다」.
  test('🎯a selection that reaches the direction row: its drawing rows go '
      'in, the direction row stays in its own place, and the order they '
      'were picked in says nothing', () {
    List<String>? shapeBefore;
    for (final directionFirst in [true, false]) {
      final s = session();
      final rows = addRows(s, 2);
      final direction = _added(s, LayerKind.instruction);
      select(
        s,
        directionFirst ? [direction, ...rows.reversed] : [...rows, direction],
      );

      final folder = addFolder(s);

      expect(
        [for (final id in rows) stackOf(s).byId(id)!.folderId],
        everyElement(folder),
        reason: 'direction picked ${directionFirst ? 'first' : 'last'}',
      );
      _expectInItsOwnPlace(s, direction);
      expect(folderStructureProblem(stackOf(s)), isNull);
      shapeBefore ??= shapeOf(s);
      expect(shapeOf(s), shapeBefore, reason: 'the same rows, the same law');
    }
  });

  test('🎯dragged onto a folder, a selection that reaches the direction row '
      'lands the same whichever of its rows the hand holds', () {
    ({EditorSessionManager s, List<LayerId> rows, LayerId direction})
    standing() {
      final s = session();
      final bottom = s.activeLayerId!;
      final rows = addRows(s, 2);
      final direction = _added(s, LayerKind.instruction);
      // The folder under the rows picked, out of the span they carry.
      s.selectLayer(bottom);
      s.rowSelection.value = const [];
      final folder = addFolder(s);
      expect(
        stackOf(s).indexWhere((layer) => layer.id == folder),
        lessThan(stackOf(s).indexWhere((layer) => layer.id == rows.first)),
        reason: '⛔premise: the folder stands under the rows',
      );
      select(s, [direction, ...rows.reversed]);
      return (s: s, rows: rows, direction: direction);
    }

    LayerId folderOf(EditorSessionManager s) => stackOf(
      s,
    ).firstWhere((layer) => layer.kind == LayerKind.folder).id;

    final byDrawing = standing();
    _dropOn(byDrawing.s, byDrawing.rows.last, folderOf(byDrawing.s));
    final byDirection = standing();
    _dropOn(byDirection.s, byDirection.direction, folderOf(byDirection.s));

    expect(
      [
        for (final id in byDrawing.rows)
          stackOf(byDrawing.s).byId(id)!.folderId,
      ],
      everyElement(folderOf(byDrawing.s)),
      reason: 'the drawing rows go in',
    );
    _expectInItsOwnPlace(byDrawing.s, byDrawing.direction);
    expect(shapeOf(byDirection.s), shapeOf(byDrawing.s));
  });

  test('🎯let go in a gap among the drawing rows, a selection that reaches '
      'the direction row moves its drawing rows there, the direction row '
      'stays, whichever row the hand holds', () {
    final s = session();
    final bottom = s.activeLayerId!;
    final rows = addRows(s, 2);
    final direction = _added(s, LayerKind.instruction);
    final stack = sectionedLayerOrder(s.requireActiveCut.layers);
    int at(LayerId id) => stack.indexWhere((layer) => layer.id == id);
    // The top drawing row, down into the gap right above the bottom one.
    final gap = at(bottom) + 1;
    final moved = [for (final layer in stack) layer.id]
      ..remove(rows.last)
      ..insert(gap, rows.last);

    for (final hand in [rows.last, direction]) {
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: hand,
        insertAt: gap,
        alsoMoving: {rows.last, direction},
      );
      expect(plan?.order, moved, reason: 'the hand on ${stack.byId(hand)}');
    }
  });

  test('🎯dropped on a folder that stands inside the span the selection '
      'reaches, its drawing row goes in, whichever row the hand holds', () {
    ({EditorSessionManager s, LayerId bottom, LayerId direction}) standing() {
      final s = session();
      final bottom = s.activeLayerId!;
      addRows(s, 2);
      final direction = _added(s, LayerKind.instruction);
      s.selectLayer(bottom);
      s.rowSelection.value = const [];
      addFolder(s);
      select(s, [direction, bottom]);
      return (s: s, bottom: bottom, direction: direction);
    }

    LayerId folderOf(EditorSessionManager s) => stackOf(
      s,
    ).firstWhere((layer) => layer.kind == LayerKind.folder).id;

    final shapes = <List<String>>[];
    for (final byBottom in [true, false]) {
      final (:s, :bottom, :direction) = standing();
      final folder = folderOf(s);
      final stack = sectionedLayerOrder(stackOf(s));
      int at(LayerId id) => stack.indexWhere((layer) => layer.id == id);
      expect(
        at(bottom) < at(folder) && at(folder) < at(direction),
        isTrue,
        reason: '⛔premise: the folder stands between the rows picked',
      );
      _dropOn(s, byBottom ? bottom : direction, folder);
      expect(stackOf(s).byId(bottom)!.folderId, folder);
      _expectInItsOwnPlace(s, direction);
      shapes.add(shapeOf(s));
    }
    expect(shapes.last, shapes.first, reason: 'the held row says nothing');
  });

  test('🎯made from a selection that reaches the direction row, the folder '
      'is born where its drawing row stood, not at the top of their '
      'section', () {
    final s = session();
    final rows = addRows(s, 2);
    final direction = _added(s, LayerKind.instruction);
    select(s, [direction, rows.first]);

    final folder = addFolder(s);

    final stack = sectionedLayerOrder(stackOf(s));
    int at(LayerId id) => stack.indexWhere((layer) => layer.id == id);
    expect(stack.byId(rows.first)!.folderId, folder);
    expect(
      [at(rows.first) < at(folder), at(folder) < at(rows.last)],
      [isTrue, isTrue],
      reason: 'the folder and its row under the drawing row not picked',
    );
    _expectInItsOwnPlace(s, direction);
  });

  test('🎯held by the direction row, a selection lands as held by the '
      'drawing row of it nearest the hand', () {
    // Where the drawing rows picked stand in different folders, which of
    // them the hand holds is an answer of its own: a gap on the edge of the
    // held row's folder keeps it in, with the pointer still in its rows
    // (F-312).
    // 🔬Measured, every gap and pointer and every row dropped on, over four
    // folder layouts and every pick of their drawing rows with the direction
    // row (11-25): 23 of 14,427 answers split by the drawing row held — this
    // layout's among them.
    final s = session();
    final rows = [s.activeLayerId!, ...addRows(s, 3)];
    select(s, [rows[0]]);
    addFolder(s);
    select(s, [rows[2], rows[3]]);
    final folder = addFolder(s);
    s.rowSelection.value = const [];
    final direction = _added(s, LayerKind.instruction);
    final stack = sectionedLayerOrder(stackOf(s));
    int at(LayerId id) => stack.indexWhere((layer) => layer.id == id);
    final (outside, member) = (rows[1], rows[2]);
    expect(
      [stack.byId(outside)!.folderId, stack.byId(member)!.folderId],
      [null, folder],
      reason: '⛔premise: one row picked outside a folder, one in it',
    );
    expect(
      at(member),
      greaterThan(at(outside)),
      reason: '⛔premise: the row in the folder is the nearer the hand',
    );

    List<String>? landed(LayerId hand) {
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: hand,
        insertAt: at(outside),
        alsoMoving: {outside, member, direction},
        pointer: PointerInRow(outside),
      );
      if (plan == null) {
        return null;
      }
      LayerId? folderOf(LayerId id) => plan.folderIds.containsKey(id)
          ? plan.folderIds[id]
          : stack.byId(id)!.folderId;
      return [
        for (final id in plan.order)
          '${stack.byId(id)!.name} in ${folderOf(id)}',
      ];
    }

    expect(
      landed(member),
      allOf(isNotNull, isNot(landed(outside))),
      reason: '⛔premise: the row held decides here',
    );
    expect(landed(direction), landed(member));
  });

  test('a track\'s row picked first with the cut\'s — the cut\'s go in', () {
    final s = session();
    final rows = addRows(s, 2);
    final se = s.layerStack.addSeLane();
    select(s, [se, ...rows]);

    final folder = addFolder(s);

    expect(
      [for (final id in rows) stackOf(s).byId(id)!.folderId],
      everyElement(folder),
    );
    expect(folderStructureProblem(stackOf(s)), isNull);
  });
}

/// The row [s] made with Add Layer's [kind], stood on.
LayerId _added(EditorSessionManager s, LayerKind kind) {
  s.layerStack.addLayerOfKind(kind);
  return s.activeLayerId!;
}

/// [direction] in no folder, above every drawing row of the cut — the
/// camera section's, where A5-4 keeps it.
void _expectInItsOwnPlace(EditorSessionManager s, LayerId direction) {
  final stack = sectionedLayerOrder(s.requireActiveCut.layers);
  final at = stack.indexWhere((layer) => layer.id == direction);
  expect(stack[at].folderId, isNull, reason: 'the direction row in a folder');
  expect(
    stack.sublist(at + 1).where(
      (layer) =>
          timelineSectionForLayerKind(layer.kind) == TimelineSection.drawing,
    ),
    isEmpty,
    reason: 'a drawing row above the direction row',
  );
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
