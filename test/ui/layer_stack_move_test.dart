import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Moving a row along the stack — the drag's twin, and the first consumer
/// of the drop policy. What is pinned here is the part a widget test cannot
/// see: that the run travels whole, that membership follows the landing,
/// that the move reaches the 겸용 siblings, and that one step is one undo.

EditorSessionManager _session() {
  final session = EditorSessionManager(initialProject: createDefaultProject());
  addTearDown(session.dispose);
  return session;
}

List<String> _drawingIds(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers)
    if (layer.kind == LayerKind.animation || layer.kind == LayerKind.folder)
      layer.id.value,
];

Layer _layerOf(EditorSessionManager session, LayerId id) =>
    session.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

void main() {
  group('a row steps along the stack', () {
    test('up and down rewrite the order, and one step is one undo', () {
      final session = _session();
      session.addLayerOfKind(LayerKind.animation);
      session.addLayerOfKind(LayerKind.animation);
      final before = _drawingIds(session);
      expect(before.length, greaterThanOrEqualTo(3));

      final bottom = LayerId(before.first);
      session.moveLayerInStack(bottom, up: true);
      expect(_drawingIds(session)[1], before.first);
      expect(_drawingIds(session).first, before[1]);

      session.undo();
      expect(_drawingIds(session), before, reason: 'one step is one undo');
    });

    test('the ends of the stack refuse', () {
      final session = _session();
      session.addLayerOfKind(LayerKind.animation);
      final ids = _drawingIds(session);
      expect(
        session.canMoveLayerInStack(LayerId(ids.first), up: false),
        isFalse,
        reason: 'nothing below the bottom row',
      );
    });

    test('a drawing row cannot step into the camera section', () {
      final session = _session();
      final drawing = session.requireActiveCut.layers
          .lastWhere((layer) => layer.kind == LayerKind.animation)
          .id;
      // Stepping up from the top drawing row would land among the SE or
      // camera rows, which the display would spring back.
      var steps = 0;
      while (session.canMoveLayerInStack(drawing, up: true) && steps < 20) {
        session.moveLayerInStack(drawing, up: true);
        steps += 1;
      }
      final layers = session.requireActiveCut.layers;
      final index = layers.indexWhere((layer) => layer.id == drawing);
      expect(
        layers
            .sublist(index + 1)
            .every((layer) => layer.kind != LayerKind.animation),
        isTrue,
        reason: 'it climbed to the top of its own section and stopped',
      );
      expect(session.canMoveLayerInStack(drawing, up: true), isFalse);
    });
  });

  group('membership follows the landing', () {
    test('stepping into a folder joins it; stepping out leaves it', () {
      final session = _session();
      session.addLayerOfKind(LayerKind.animation);
      session.addLayerOfKind(LayerKind.animation);
      final drawing = [
        for (final layer in session.requireActiveCut.layers)
          if (layer.kind == LayerKind.animation) layer.id,
      ];
      // The TOP drawing row becomes a folder's member; the one below it is
      // the traveller.
      session.selectLayer(drawing.last);
      session.groupActiveLayerIntoFolder();
      final folder = session.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.folder)
          .id;
      final traveller = drawing[drawing.length - 2];
      expect(_layerOf(session, traveller).folderId, isNull);

      // Up: the row above it is the folder's first MEMBER, so stepping past
      // that member lands inside the folder.
      session.moveLayerInStack(traveller, up: true);
      expect(_layerOf(session, traveller).folderId, folder);

      // Up again: past the folder ROW, whose subtree ends there.
      session.moveLayerInStack(traveller, up: true);
      expect(_layerOf(session, traveller).folderId, isNull);

      // And back in.
      session.moveLayerInStack(traveller, up: false);
      expect(_layerOf(session, traveller).folderId, folder);
    });

    test('a folder travels whole', () {
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

      session.moveLayerInStack(folder, up: false);
      final layers = session.requireActiveCut.layers;
      final folderIndex = layers.indexWhere((layer) => layer.id == folder);
      final memberIndex = layers.indexWhere((layer) => layer.id == member);
      expect(
        memberIndex,
        folderIndex - 1,
        reason: 'the member came with it, still directly below the folder',
      );
      expect(_layerOf(session, member).folderId, folder);
    });
  });

  group('order is shared structure', () {
    test('a move reaches the 겸용 sibling cut', () {
      final session = _session();
      session.addLayerOfKind(LayerKind.animation);
      final sourceCutId = session.requireActiveCut.id;
      final sourceOrder = _drawingIds(session);
      session.createLinkedCutFromActiveCut();
      final linkedCutId = session.requireActiveCut.id;
      expect(linkedCutId, isNot(sourceCutId));
      final linkedOrderBefore = _drawingIds(session);

      // Back to the source cut, and move its bottom drawing row up.
      session.selectCut(sourceCutId);
      session.moveLayerInStack(LayerId(sourceOrder.first), up: true);
      final sourceAfter = _drawingIds(session);
      expect(sourceAfter, isNot(sourceOrder));

      session.selectCut(linkedCutId);
      final linkedAfter = _drawingIds(session);
      expect(
        linkedAfter,
        isNot(linkedOrderBefore),
        reason: 'the sibling stack moved with it — order is structure',
      );
      // The two stacks still read the same shape, row for row.
      expect(linkedAfter.length, sourceAfter.length);
    });
  });

  group('SE rows are the track\'s own list', () {
    test('a step rewrites the track order', () {
      final session = _session();
      final rows = [for (final row in session.activeTrack.seLayers) row.id];
      expect(rows.length, greaterThanOrEqualTo(2));

      session.moveLayerInStack(rows.first, up: true);
      expect(
        [for (final row in session.activeTrack.seLayers) row.id],
        [rows[1], rows.first, ...rows.skip(2)],
      );
    });
  });
}
