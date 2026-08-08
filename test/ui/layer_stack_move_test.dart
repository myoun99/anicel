import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowSubject;

/// Moving a row along the stack, driven through the DRAG — the only way a
/// user can do it since R5 #5 retired the step verbs.
///
/// What is pinned here is the part the widget test cannot see: that a run
/// travels whole, that the move reaches the 겸용 siblings, that one drag is
/// one undo, and that a refused landing commits nothing. Where the landing
/// LANDS is `layer_drop_policy_test`'s; how the pointer names it is
/// `layer_row_drag_test`'s. This is the commit path between them.

EditorSessionManager _session() {
  final session = EditorSessionManager(initialProject: createDefaultProject());
  addTearDown(session.dispose);
  return session;
}

/// One whole drag, landing [id] at model index [insertAt].
///
/// The display list handed over is the MODEL order, which is a surface the
/// x-sheet really renders — and with the two lists identical the slot IS
/// the model insertion index, so these tests state landings in the terms
/// the stack itself uses rather than in a rail's reversed ones.
void _dragTo(EditorSessionManager session, LayerId id, int insertAt) {
  session.beginLayerRowDrag(LayerRowSubject(id));
  session.updateLayerRowDrag(session.layers, insertAt);
  session.endLayerRowDrag();
}

List<String> _drawingIds(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers)
    if (layer.kind == LayerKind.animation || layer.kind == LayerKind.folder)
      layer.id.value,
];

Layer _layerOf(EditorSessionManager session, LayerId id) =>
    session.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

int _indexOf(EditorSessionManager session, LayerId id) =>
    session.requireActiveCut.layers.indexWhere((layer) => layer.id == id);

void main() {
  test('one drag is one undo', () {
    final session = _session();
    session.addLayerOfKind(LayerKind.animation);
    session.addLayerOfKind(LayerKind.animation);
    final before = _drawingIds(session);
    expect(before.length, greaterThanOrEqualTo(3));

    final bottom = LayerId(before.first);
    _dragTo(session, bottom, _indexOf(session, LayerId(before[1])) + 1);
    expect(_drawingIds(session), isNot(before));
    expect(_drawingIds(session)[0], before[1]);
    expect(_drawingIds(session)[1], before.first);

    session.undo();
    expect(_drawingIds(session), before, reason: 'one drag is one undo');
  });

  test('a refused landing commits nothing — a drawing row cannot cross into '
      'the camera section', () {
    final session = _session();
    final drawing = session.requireActiveCut.layers
        .lastWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    final before = [
      for (final layer in session.requireActiveCut.layers) layer.id.value,
    ];

    // The very top of the stack is past every section boundary above the
    // drawing rows; the display re-buckets by kind, so a landing there
    // would spring straight back.
    _dragTo(session, drawing, session.layers.length);

    expect([
      for (final layer in session.requireActiveCut.layers) layer.id.value,
    ], before);
  });

  test('a folder travels whole, and its members stay directly below it', () {
    final session = _session();
    session.addLayerOfKind(LayerKind.animation);
    final member = session.requireActiveCut.layers
        .lastWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(member);
    session.groupActiveLayerIntoFolder();
    final folder = session.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.folder)
        .id;

    _dragTo(session, folder, 0);

    final folderIndex = _indexOf(session, folder);
    expect(
      _indexOf(session, member),
      folderIndex - 1,
      reason: 'the member came with it, still directly below the folder',
    );
    expect(_layerOf(session, member).folderId, folder);
  });

  test('a move reaches the 겸용 sibling cut — order is shared structure', () {
    final session = _session();
    session.addLayerOfKind(LayerKind.animation);
    final sourceCutId = session.requireActiveCut.id;
    final sourceOrder = _drawingIds(session);
    session.createLinkedCutFromActiveCut();
    final linkedCutId = session.requireActiveCut.id;
    expect(linkedCutId, isNot(sourceCutId));
    final linkedOrderBefore = _drawingIds(session);

    session.selectCut(sourceCutId);
    final bottom = LayerId(sourceOrder.first);
    _dragTo(session, bottom, _indexOf(session, LayerId(sourceOrder[1])) + 1);
    final sourceAfter = _drawingIds(session);
    expect(sourceAfter, isNot(sourceOrder));

    session.selectCut(linkedCutId);
    final linkedAfter = _drawingIds(session);
    expect(
      linkedAfter,
      isNot(linkedOrderBefore),
      reason: 'the sibling stack moved with it — order is structure',
    );
    expect(linkedAfter.length, sourceAfter.length);
  });

  test('SE rows re-order the TRACK\'s own list', () {
    final session = _session();
    final rows = [for (final row in session.activeTrack.seLayers) row.id];
    expect(rows.length, greaterThanOrEqualTo(2));

    // The SE arm reads the track's list as both the model and the display,
    // so slot 2 is "after the second row".
    session.beginLayerRowDrag(LayerRowSubject(rows.first));
    session.updateLayerRowDrag(session.activeTrack.seLayers, 2);
    session.endLayerRowDrag();

    expect(
      [for (final row in session.activeTrack.seLayers) row.id],
      [rows[1], rows.first, ...rows.skip(2)],
    );
  });
}
